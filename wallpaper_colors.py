#!/usr/bin/env python3

import argparse
import colorsys
import math
import os
import sys
from collections import Counter

from PIL import Image


ANALYSIS_SIZE = 500

# Wallpaper filtering.
BLACK_THRESHOLD = 0.10
WHITE_THRESHOLD = 0.92
MIN_SATURATION = 0.12

# Dominant-color quantization.
#
# Smaller values preserve more detail.
# Larger values group more similar colors together.
DOMINANT_COLOR_BIN_SIZE = 16

# Theme-color filtering.
#
# We only want vibrant accent colors to compete.
# Backgrounds, dark grays, near-whites, and dull colors are excluded.
MATCH_MIN_LIGHTNESS = 0.35
MATCH_MAX_LIGHTNESS = 0.94
MATCH_MIN_CHROMA = 0.06

XRESOURCES_PATH = os.path.expanduser(
    "~/.cache/theme-gen/colors.Xresources"
)

DUNST_PATH = os.path.expanduser(
    "~/.config/dunst/dunstrc"
)


THEMES = {
    "catppuccin": {
        "display_name": "Catppuccin Mocha",

        # DWM base colors.
        "background": "#1E1E2E",
        "foreground": "#CDD6F4",
        "background_sel": "#313244",
        "border": "#585B70",

        # DWM accent colors.
        #
        # These are used as selectable theme colors and are intentionally
        # separate from the ST ANSI palette.
        "dwm_colors": {
            "red": ("Maroon", "#EBA0AC"),
            "green": ("Green", "#A6E3A1"),
            "yellow": ("Yellow", "#F9E2AF"),
            "blue": ("Sky", "#89DCEB"),
            "purple": ("Mauve", "#CBA6F7"),
            "cyan": ("Teal", "#94E2D5"),
        },

        # Exact Catppuccin Mocha ST / DWM bar ANSI palette.
        "terminal": [
            "#45475A",
            "#F38BA8",
            "#A6E3A1",
            "#F9E2AF",
            "#89B4FA",
            "#F5C2E7",
            "#94E2D5",
            "#BAC2DE",

            "#585B70",
            "#F38BA8",
            "#A6E3A1",
            "#F9E2AF",
            "#89B4FA",
            "#F5C2E7",
            "#94E2D5",
            "#A6ADC8",
        ],

        "terminal_foreground": "#CDD6F4",
        "terminal_background": "#1E1E2E",
        "terminal_cursor": "#F5E0DC",
        "terminal_cursor_reverse": "#F5E0DC",
    },

    "gruvbox": {
        "display_name": "Gruvbox Dark",

        # DWM base colors.
        "background": "#282828",
        "foreground": "#EBDBB2",
        "background_sel": "#3C3836",
        "border": "#928374",

        # DWM accent colors.
        "dwm_colors": {
            "red": ("Bright Red", "#FB4934"),
            "green": ("Bright Green", "#B8BB26"),
            "yellow": ("Bright Yellow", "#FABD2F"),
            "blue": ("Bright Blue", "#83A598"),
            "purple": ("Bright Purple", "#D3869B"),
            "cyan": ("Bright Aqua", "#8EC07C"),
        },

        # Exact dark Gruvbox ST / DWM bar ANSI palette.
        "terminal": [
            "#282828",
            "#CC241D",
            "#98971A",
            "#D79921",
            "#458588",
            "#B16286",
            "#689D6A",
            "#A89984",

            "#928374",
            "#FB4934",
            "#B8BB26",
            "#FABD2F",
            "#83A598",
            "#D3869B",
            "#8EC07C",
            "#EBDBB2",
        ],

        "terminal_foreground": "#EBDBB2",
        "terminal_background": "#282828",
        "terminal_cursor": "#EBDBB2",
        "terminal_cursor_reverse": "#282828",
    },
}


def hex_to_rgb(hex_color):
    """Convert #RRGGBB to RGB values in the 0.0-1.0 range."""
    hex_color = hex_color.lstrip("#")

    if len(hex_color) != 6:
        raise ValueError(
            f"Invalid color: #{hex_color}"
        )

    return tuple(
        int(hex_color[i:i + 2], 16) / 255.0
        for i in (0, 2, 4)
    )


def srgb_to_linear(value):
    """Convert an sRGB component to linear RGB."""
    if value <= 0.04045:
        return value / 12.92

    return ((value + 0.055) / 1.055) ** 2.4


def rgb_to_oklab(hex_color):
    """
    Convert an sRGB hex color to OKLab.

    Returns:
        (L, a, b)
    """
    r, g, b = hex_to_rgb(hex_color)

    r = srgb_to_linear(r)
    g = srgb_to_linear(g)
    b = srgb_to_linear(b)

    l = (
        0.4122214708 * r
        + 0.5363325363 * g
        + 0.0514459929 * b
    )

    m = (
        0.2119034982 * r
        + 0.6806995451 * g
        + 0.1073969566 * b
    )

    s = (
        0.0883024619 * r
        + 0.2817188376 * g
        + 0.6299787005 * b
    )

    l_ = l ** (1 / 3)
    m_ = m ** (1 / 3)
    s_ = s ** (1 / 3)

    return (
        0.2104542553 * l_
        + 0.7936177850 * m_
        - 0.0040720468 * s_,
        1.9779984951 * l_
        - 2.4285922050 * m_
        + 0.4505937099 * s_,
        0.0259040371 * l_
        + 0.7827717662 * m_
        - 0.8086757662 * s_,
    )


def rgb_to_oklch(hex_color):
    """
    Convert an sRGB hex color to OKLCH.

    Returns:
        L = perceptual lightness
        C = chroma
        H = hue in radians
    """
    L, a, b = rgb_to_oklab(hex_color)

    C = math.sqrt(
        (a * a) + (b * b)
    )

    H = math.atan2(b, a)

    return L, C, H


def color_distance(color_a, color_b):
    """
    Return Euclidean distance between two colors in OKLab.
    """
    a = rgb_to_oklab(color_a)
    b = rgb_to_oklab(color_b)

    return math.sqrt(
        (a[0] - b[0]) ** 2
        + (a[1] - b[1]) ** 2
        + (a[2] - b[2]) ** 2
    )


def oklch_distance(color_a, color_b):
    """
    Return a hue-aware perceptual distance between two colors.

    This is intentionally not a simple RGB distance.

    Hue is weighted heavily so that a dark blue/purple wallpaper
    doesn't accidentally become red simply because several light
    theme colors have similar overall OKLab distance.

    Lightness and chroma are also considered.
    """
    L1, C1, H1 = rgb_to_oklch(color_a)
    L2, C2, H2 = rgb_to_oklch(color_b)

    hue_difference = abs(H1 - H2)

    if hue_difference > math.pi:
        hue_difference = (
            (2.0 * math.pi) - hue_difference
        )

    hue_difference /= math.pi

    lightness_difference = abs(
        L1 - L2
    )

    chroma_difference = abs(
        C1 - C2
    )

    # Normalize chroma into a useful range.
    chroma_difference = min(
        chroma_difference / 0.40,
        1.0,
    )

    # Hue is the most important part of the relationship.
    #
    # This gives us behavior closer to how a human would describe
    # the wallpaper:
    #
    #   purple-ish image -> purple accent
    #   blue-ish image   -> blue accent
    #   orange-ish image -> yellow/red accent
    #
    # while still allowing lightness/chroma to influence the result.
    return (
        (hue_difference * 0.65)
        + (lightness_difference * 0.15)
        + (chroma_difference * 0.20)
    )


def get_saturation(rgb):
    """Return HSV saturation for an RGB tuple."""
    r, g, b = rgb

    _, saturation, _ = colorsys.rgb_to_hsv(
        r,
        g,
        b,
    )

    return saturation


def should_ignore(rgb):
    """
    Ignore black, white, and low-saturation pixels.
    """
    r, g, b = rgb

    brightness = (
        r + g + b
    ) / 3.0

    saturation = get_saturation(
        rgb
    )

    if brightness <= BLACK_THRESHOLD:
        return True

    if brightness >= WHITE_THRESHOLD:
        return True

    if saturation < MIN_SATURATION:
        return True

    return False


def rgb_tuple_to_hex(rgb):
    """Convert an RGB tuple in 0.0-1.0 range to #RRGGBB."""
    r, g, b = rgb

    return "#{:02X}{:02X}{:02X}".format(
        round(r * 255),
        round(g * 255),
        round(b * 255),
    )


def rgb_int_tuple_to_hex(rgb):
    """Convert an RGB tuple in 0-255 range to #RRGGBB."""
    r, g, b = rgb

    return "#{:02X}{:02X}{:02X}".format(
        r,
        g,
        b,
    )


def is_vibrant_theme_color(hex_color):
    """
    Return True if a theme color is suitable for matching.

    Dark backgrounds, near-whites, and gray/dull colors are excluded.
    """
    L, C, _ = rgb_to_oklch(
        hex_color
    )

    if L < MATCH_MIN_LIGHTNESS:
        return False

    if L > MATCH_MAX_LIGHTNESS:
        return False

    if C < MATCH_MIN_CHROMA:
        return False

    return True


def analyze_wallpaper(path):
    """
    Find the dominant actual color in the wallpaper.

    The process is:

        1. Resize the image.
        2. Remove black, white, gray and dull pixels.
        3. Quantize remaining colors into bins.
        4. Find the most frequently occurring color bin.
        5. Average the original pixels belonging to that bin.

    This gives us an actual dominant color rather than simply
    declaring an image "blue" because most of its pixels fall
    into a broad HSV hue bucket.
    """

    try:
        image = Image.open(path)
    except FileNotFoundError:
        raise FileNotFoundError(
            f"file not found: {path}"
        )
    except Exception as exc:
        raise RuntimeError(
            f"could not open wallpaper: {exc}"
        )

    image = image.convert("RGB")

    image.thumbnail(
        (
            ANALYSIS_SIZE,
            ANALYSIS_SIZE,
        )
    )

    # Pillow 14+ compatible.
    try:
        pixels = image.get_flattened_data()
    except AttributeError:
        pixels = list(
            image.getdata()
        )

    usable_pixels = []

    for pixel in pixels:
        rgb = tuple(
            channel / 255.0
            for channel in pixel
        )

        if should_ignore(rgb):
            continue

        usable_pixels.append(
            pixel
        )

    if not usable_pixels:
        raise RuntimeError(
            "no sufficiently saturated colored pixels "
            "were found in the wallpaper"
        )

    # ------------------------------------------------------------
    # Quantize the image.
    #
    # Exact RGB values are too specific because photographs contain
    # thousands of subtly different shades.
    #
    # For example:
    #
    #   31,31,46
    #   32,31,47
    #   30,32,45
    #   33,31,46
    #
    # should all count as essentially the same color.
    # ------------------------------------------------------------

    bin_size = DOMINANT_COLOR_BIN_SIZE

    color_bins = Counter()

    for pixel in usable_pixels:
        r, g, b = pixel

        bucket = (
            r // bin_size,
            g // bin_size,
            b // bin_size,
        )

        color_bins[bucket] += 1

    dominant_bucket, dominant_count = (
        color_bins.most_common(1)[0]
    )

    # ------------------------------------------------------------
    # Recover the actual average color represented by the dominant
    # quantized bucket.
    # ------------------------------------------------------------

    dominant_pixels = []

    for pixel in usable_pixels:
        r, g, b = pixel

        bucket = (
            r // bin_size,
            g // bin_size,
            b // bin_size,
        )

        if bucket == dominant_bucket:
            dominant_pixels.append(
                pixel
            )

    dominant_average = tuple(
        sum(
            pixel[channel]
            for pixel in dominant_pixels
        ) / len(dominant_pixels)
        for channel in range(3)
    )

    dominant_color = rgb_int_tuple_to_hex(
        tuple(
            round(value)
            for value in dominant_average
        )
    )

    # Calculate the overall average as additional diagnostic info.
    overall_average = tuple(
        sum(
            pixel[channel]
            for pixel in usable_pixels
        ) / len(usable_pixels)
        for channel in range(3)
    )

    overall_average_color = rgb_int_tuple_to_hex(
        tuple(
            round(value)
            for value in overall_average
        )
    )

    return {
        "dominant_color": dominant_color,
        "dominant_count": dominant_count,
        "dominant_percentage": (
            dominant_count
            / len(usable_pixels)
        ) * 100.0,
        "overall_average_color": (
            overall_average_color
        ),
        "usable_pixels": len(
            usable_pixels
        ),
    }


def get_theme_match_colors(theme):
    """
    Build the palette of colors that are allowed to compete.

    We intentionally look through the entire theme instead of
    mapping a hue family directly to one DWM color.
    """

    candidates = []

    # ------------------------------------------------------------
    # DWM accent colors.
    # ------------------------------------------------------------

    for name, color in theme["dwm_colors"].values():
        candidates.append(
            (
                name,
                color,
                "DWM",
            )
        )

    # ------------------------------------------------------------
    # ST ANSI accent colors.
    #
    # Only actual colored ANSI entries are considered.
    #
    # 1/9   red
    # 2/10  green
    # 3/11  yellow
    # 4/12  blue
    # 5/13  purple
    # 6/14  cyan
    # ------------------------------------------------------------

    terminal = theme["terminal"]

    terminal_names = {
        1: "Red",
        2: "Green",
        3: "Yellow",
        4: "Blue",
        5: "Purple",
        6: "Cyan",

        9: "Bright Red",
        10: "Bright Green",
        11: "Bright Yellow",
        12: "Bright Blue",
        13: "Bright Purple",
        14: "Bright Cyan",
    }

    for index, name in terminal_names.items():
        candidates.append(
            (
                name,
                terminal[index],
                "ST",
            )
        )

    # ------------------------------------------------------------
    # Remove duplicate colors.
    # ------------------------------------------------------------

    unique = []
    seen = set()

    for name, color, source in candidates:
        color = color.upper()

        if color in seen:
            continue

        seen.add(color)

        unique.append(
            (
                name,
                color,
                source,
            )
        )

    # ------------------------------------------------------------
    # Remove dark / white / dull colors.
    # ------------------------------------------------------------

    vibrant = [
        candidate
        for candidate in unique
        if is_vibrant_theme_color(
            candidate[1]
        )
    ]

    return vibrant


def find_dwm_color(theme, wallpaper_color):
    """
    Find the theme color most closely related to the dominant
    wallpaper color.

    Every vibrant theme accent competes against every other accent.

    There is deliberately NO:

        blue -> Sky
        purple -> Mauve
        cyan -> Teal

    mapping anymore.
    """

    candidates = get_theme_match_colors(
        theme
    )

    if not candidates:
        raise RuntimeError(
            "theme contains no suitable vibrant colors "
            "for wallpaper matching"
        )

    ranked = []

    for name, color, source in candidates:
        distance = oklch_distance(
            wallpaper_color,
            color,
        )

        raw_oklab_distance = color_distance(
            wallpaper_color,
            color,
        )

        wallpaper_L, wallpaper_C, wallpaper_H = (
            rgb_to_oklch(
                wallpaper_color
            )
        )

        color_L, color_C, color_H = (
            rgb_to_oklch(
                color
            )
        )

        hue_difference = abs(
            wallpaper_H - color_H
        )

        if hue_difference > math.pi:
            hue_difference = (
                (2.0 * math.pi)
                - hue_difference
            )

        hue_difference_degrees = math.degrees(
            hue_difference
        )

        ranked.append(
            {
                "name": name,
                "color": color,
                "source": source,
                "distance": distance,
                "oklab_distance": raw_oklab_distance,
                "hue_difference": (
                    hue_difference_degrees
                ),
            }
        )

    ranked.sort(
        key=lambda item: item["distance"]
    )

    winner = ranked[0]

    winner["candidates"] = ranked

    return winner


def generate_xresources(theme, dwm_color):
    """
    Generate Xresources for DWM, dmenu, slock and ST.
    """

    os.makedirs(
        os.path.dirname(
            XRESOURCES_PATH
        ),
        exist_ok=True,
    )

    terminal = theme["terminal"]

    lines = [
        "! ============================================================",
        "! Generated wallpaper theme",
        "! ============================================================",
        "",
        f"! Theme: {theme['display_name']}",
        "",
        "! ============================================================",
        "! dwm",
        "! ============================================================",
        "",
        f"dwm.foreground: {theme['foreground']}",
        f"dwm.background: {theme['background']}",
        f"dwm.border: {theme['border']}",
        f"dwm.foregroundSel: {theme['background']}",
        f"dwm.backgroundSel: {dwm_color['color']}",
        f"dwm.borderSel: {dwm_color['color']}",
        "",
        "! ============================================================",
        "! dwm status bar ANSI colors",
        "! These intentionally use the exact ST terminal palette.",
        "! ============================================================",
        "",
    ]

    for index, color in enumerate(
        terminal
    ):
        lines.append(
            f"dwm.barcolor{index}: {color}"
        )

    lines.extend([
        "",
        "! ============================================================",
        "! dmenu",
        "! ============================================================",
        "",
        f"dmenu.foreground: {theme['foreground']}",
        f"dmenu.background: {theme['background']}",
        f"dmenu.foregroundSel: {theme['background']}",
        f"dmenu.backgroundSel: {dwm_color['color']}",
        f"dmenu.foregroundOut: {theme['foreground']}",
        f"dmenu.backgroundOut: {theme['background']}",
        "",
        "! ============================================================",
        "! slock",
        "! ============================================================",
        "",
        f"slock.color0: {theme['background']}",
        f"slock.color4: {dwm_color['color']}",
        f"slock.color1: {theme['dwm_colors']['red'][1]}",
        f"slock.color3: {theme['dwm_colors']['yellow'][1]}",
        "",
        "! ============================================================",
        "! st",
        "! ============================================================",
        "",
    ])

    for index, color in enumerate(
        terminal
    ):
        lines.append(
            f"st.color{index}: {color}"
        )

    lines.extend([
        "",
        (
            f"st.foreground: "
            f"{theme['terminal_foreground']}"
        ),
        (
            f"st.background: "
            f"{theme['terminal_background']}"
        ),
        (
            f"st.cursorColor: "
            f"{theme['terminal_cursor']}"
        ),
        (
            "st.cursorColorReverse: "
            f"{theme['terminal_cursor_reverse']}"
        ),
        "",
    ])

    with open(
        XRESOURCES_PATH,
        "w",
        encoding="utf-8",
    ) as file:
        file.write(
            "\n".join(lines)
        )


def generate_dunst(theme, dwm_color):
    """
    Generate ~/.config/dunst/dunstrc.
    """

    os.makedirs(
        os.path.dirname(
            DUNST_PATH
        ),
        exist_ok=True,
    )

    low_frame = theme["border"]
    normal_frame = dwm_color["color"]
    critical_frame = (
        theme["dwm_colors"]["red"][1]
    )

    content = f"""[global]
font = JetBrains Mono 10
frame_width = 3
corner_radius = 0
separator_height = 2

[urgency_low]
background = "{theme['background']}"
foreground = "{theme['foreground']}"
frame_color = "{low_frame}"

[urgency_normal]
background = "{theme['background']}"
foreground = "{theme['foreground']}"
frame_color = "{normal_frame}"

[urgency_critical]
background = "{theme['background']}"
foreground = "{theme['foreground']}"
frame_color = "{critical_frame}"
"""

    with open(
        DUNST_PATH,
        "w",
        encoding="utf-8",
    ) as file:
        file.write(
            content
        )


def print_usage():
    print(
        "Usage:\n"
        "  python wallpaper_colors.py "
        "WALLPAPER --theme THEME\n\n"
        "Themes:\n"
        "  catppuccin\n"
        "  gruvbox\n\n"
        "Example:\n"
        "  python wallpaper_colors.py "
        "~/Pictures/Wallpapers/5120x2880.png "
        "--theme catppuccin"
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Generate Xresources and Dunst colors "
            "from a wallpaper."
        )
    )

    parser.add_argument(
        "wallpaper",
        help="Path to the wallpaper",
    )

    parser.add_argument(
        "--theme",
        required=True,
        choices=sorted(
            THEMES.keys()
        ),
        help="Theme to use",
    )

    args = parser.parse_args()

    wallpaper = os.path.expanduser(
        args.wallpaper
    )

    theme_name = args.theme.lower()

    if not os.path.isfile(
        wallpaper
    ):
        print(
            f"Error: file not found: {wallpaper}",
            file=sys.stderr,
        )
        return 1

    theme = THEMES[
        theme_name
    ]

    # ------------------------------------------------------------
    # Analyze wallpaper.
    # ------------------------------------------------------------

    try:
        analysis = analyze_wallpaper(
            wallpaper
        )
    except Exception as exc:
        print(
            f"Error: {exc}",
            file=sys.stderr,
        )
        return 1

    dominant_color = (
        analysis["dominant_color"]
    )

    # ------------------------------------------------------------
    # Find the closest vibrant theme color.
    # ------------------------------------------------------------

    try:
        dwm_color = find_dwm_color(
            theme,
            dominant_color,
        )
    except Exception as exc:
        print(
            f"Error finding theme color: {exc}",
            file=sys.stderr,
        )
        return 1

    # ------------------------------------------------------------
    # Generate configuration files.
    # ------------------------------------------------------------

    try:
        generate_xresources(
            theme,
            dwm_color,
        )

        generate_dunst(
            theme,
            dwm_color,
        )
    except OSError as exc:
        print(
            f"Error writing generated files: {exc}",
            file=sys.stderr,
        )
        return 1

    # ------------------------------------------------------------
    # Output.
    # ------------------------------------------------------------

    print()
    print("=" * 60)
    print("Wallpaper Theme Generator")
    print("=" * 60)
    print()

    print(
        f"Theme:              "
        f"{theme['display_name']}"
    )

    print(
        f"Wallpaper:          "
        f"{wallpaper}"
    )

    print(
        f"Usable pixels:      "
        f"{analysis['usable_pixels']}"
    )

    print(
        f"Dominant color:     "
        f"{dominant_color}"
    )

    print(
        f"Dominant occurrence:"
        f" {analysis['dominant_percentage']:.2f}%"
    )

    print(
        f"Overall average:    "
        f"{analysis['overall_average_color']}"
    )

    print()

    print(
        f"Matched color:      "
        f"{dwm_color['name']}"
    )

    print(
        f"Matched hex:        "
        f"{dwm_color['color']}"
    )

    print(
        f"Color source:       "
        f"{dwm_color['source']}"
    )

    print(
        f"Hue difference:     "
        f"{dwm_color['hue_difference']:.1f}°"
    )

    print(
        f"OKLab distance:     "
        f"{dwm_color['oklab_distance']:.4f}"
    )

    print()

    # ------------------------------------------------------------
    # Show the nearest theme colors for debugging.
    # ------------------------------------------------------------

    print(
        "Closest theme colors:"
    )

    for candidate in (
        dwm_color["candidates"][:5]
    ):
        print(
            f"  {candidate['name']:<14} "
            f"{candidate['color']}  "
            f"score={candidate['distance']:.4f}"
        )

    print()

    print("Generated:")

    print(
        f"  Xresources: "
        f"{XRESOURCES_PATH}"
    )

    print(
        f"  Dunst:      "
        f"{DUNST_PATH}"
    )

    print()

    print("DWM colors:")

    print(
        f"  background:    "
        f"{theme['background']}"
    )

    print(
        f"  foreground:    "
        f"{theme['foreground']}"
    )

    print(
        f"  border:        "
        f"{theme['border']}"
    )

    print(
        f"  backgroundSel: "
        f"{dwm_color['color']}"
    )

    print(
        f"  foregroundSel: "
        f"{theme['background']}"
    )

    print(
        f"  borderSel:     "
        f"{dwm_color['color']}"
    )

    print()

    print("Dmenu colors:")

    print(
        f"  background:    "
        f"{theme['background']}"
    )

    print(
        f"  foreground:    "
        f"{theme['foreground']}"
    )

    print(
        f"  backgroundSel: "
        f"{dwm_color['color']}"
    )

    print(
        f"  foregroundSel: "
        f"{theme['background']}"
    )

    print(
        f"  backgroundOut: "
        f"{theme['background']}"
    )

    print(
        f"  foregroundOut: "
        f"{theme['foreground']}"
    )

    print()

    print("Slock colors:")

    print(
        f"  color0: "
        f"{theme['background']}"
    )

    print(
        f"  color4: "
        f"{dwm_color['color']}"
    )

    print(
        f"  color1: "
        f"{theme['dwm_colors']['red'][1]}"
    )

    print(
        f"  color3: "
        f"{theme['dwm_colors']['yellow'][1]}"
    )

    print()

    print("Dunst:")

    print(
        f"  normal frame:   "
        f"{dwm_color['color']}"
    )

    print(
        f"  critical frame: "
        f"{theme['dwm_colors']['red'][1]}"
    )

    print()

    print("=" * 60)

    return 0


if __name__ == "__main__":
    sys.exit(main())
