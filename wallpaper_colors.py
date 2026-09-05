#!/usr/bin/env python3

import argparse
import colorsys
import os
import sys
from collections import Counter

from PIL import Image


ANALYSIS_SIZE = 500
BLACK_THRESHOLD = 0.10
WHITE_THRESHOLD = 0.92
MIN_SATURATION = 0.12

XRESOURCES_PATH = os.path.expanduser(
    "~/.cache/theme-gen/colors.Xresources"
)
DUNST_PATH = os.path.expanduser(
    "~/.config/dunst/dunstrc"
)


THEMES = {
    "catppuccin": {
        "display_name": "Catppuccin Mocha",

        # DWM base colors
        "background": "#1E1E2E",
        "foreground": "#CDD6F4",
        "background_sel": "#313244",
        "border": "#585B70",

        # DWM family colors.
        #
        # These are intentionally separate from the ST ANSI palette.
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

        # DWM base colors
        "background": "#282828",
        "foreground": "#EBDBB2",
        "background_sel": "#3C3836",
        "border": "#928374",

        # Bright Gruvbox colors for DWM family matching.
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
        raise ValueError(f"Invalid color: #{hex_color}")

    return tuple(
        int(hex_color[i:i + 2], 16) / 255.0
        for i in (0, 2, 4)
    )


def srgb_to_linear(value):
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
        - 0.8086757660 * s_,
    )


def color_distance(color_a, color_b):
    """Return Euclidean distance between two colors in OKLab."""
    a = rgb_to_oklab(color_a)
    b = rgb_to_oklab(color_b)

    return (
        (a[0] - b[0]) ** 2
        + (a[1] - b[1]) ** 2
        + (a[2] - b[2]) ** 2
    ) ** 0.5


def get_saturation(rgb):
    """Return HSV saturation for an RGB tuple."""
    r, g, b = rgb
    _, saturation, _ = colorsys.rgb_to_hsv(r, g, b)
    return saturation


def should_ignore(rgb):
    """
    Ignore black, white, and low-saturation pixels.

    These thresholds intentionally remain unchanged.
    """
    r, g, b = rgb

    brightness = (r + g + b) / 3.0
    saturation = get_saturation(rgb)

    if brightness <= BLACK_THRESHOLD:
        return True

    if brightness >= WHITE_THRESHOLD:
        return True

    if saturation < MIN_SATURATION:
        return True

    return False


def classify_family(rgb):
    """
    Classify an RGB color into a broad hue family.

    These hue thresholds intentionally remain unchanged.
    """
    r, g, b = rgb
    hue, _, _ = colorsys.rgb_to_hsv(r, g, b)
    hue *= 360.0

    if hue < 15 or hue >= 345:
        return "red"

    if hue < 75:
        return "yellow"

    if hue < 145:
        return "green"

    if hue < 195:
        return "cyan"

    if hue < 255:
        return "blue"

    return "purple"


def rgb_tuple_to_hex(rgb):
    r, g, b = rgb

    return "#{:02X}{:02X}{:02X}".format(
        round(r * 255),
        round(g * 255),
        round(b * 255),
    )


def analyze_wallpaper(path):
    """
    Analyze the wallpaper using the occurrence-based method.

    Black, white, gray, and low-saturation pixels are ignored.
    The dominant family is the family with the highest occurrence.
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
    image.thumbnail((ANALYSIS_SIZE, ANALYSIS_SIZE))

    # Pillow 14+ compatible.
    try:
        pixels = image.get_flattened_data()
    except AttributeError:
        pixels = list(image.getdata())

    family_counts = Counter()
    family_rgb_totals = {}

    colored_pixels = []

    for pixel in pixels:
        rgb = tuple(
            channel / 255.0
            for channel in pixel
        )

        if should_ignore(rgb):
            continue

        family = classify_family(rgb)

        family_counts[family] += 1

        if family not in family_rgb_totals:
            family_rgb_totals[family] = [0.0, 0.0, 0.0]

        family_rgb_totals[family][0] += rgb[0]
        family_rgb_totals[family][1] += rgb[1]
        family_rgb_totals[family][2] += rgb[2]

        colored_pixels.append(rgb)

    total_colored = sum(family_counts.values())

    if total_colored == 0:
        raise RuntimeError(
            "no sufficiently saturated colored pixels were found "
            "in the wallpaper"
        )

    family_percentages = {
        family: (count / total_colored) * 100.0
        for family, count in family_counts.items()
    }

    dominant_family, dominant_count = (
        family_counts.most_common(1)[0]
    )

    dominant_rgb_total = family_rgb_totals[dominant_family]

    dominant_average = tuple(
        value / dominant_count
        for value in dominant_rgb_total
    )

    average_rgb = tuple(
        sum(
            pixel[channel]
            for pixel in colored_pixels
        ) / len(colored_pixels)
        for channel in range(3)
    )

    family_average_colors = {}

    for family, count in family_counts.items():
        rgb_total = family_rgb_totals[family]

        average = tuple(
            value / count
            for value in rgb_total
        )

        family_average_colors[family] = (
            rgb_tuple_to_hex(average)
        )

    return {
        "average_color": rgb_tuple_to_hex(average_rgb),
        "dominant_color": rgb_tuple_to_hex(
            dominant_average
        ),
        "dominant_family": dominant_family,
        "dominant_percentage": (
            dominant_count / total_colored
        ) * 100.0,
        "family_percentages": family_percentages,
        "family_average_colors": family_average_colors,
    }


def find_dwm_color(theme, family, wallpaper_color):
    """
    Select the DWM color for the dominant wallpaper family.

    The DWM family color is explicitly defined by the theme.
    OKLab distance is calculated for reporting.
    """
    name, hex_color = theme["dwm_colors"][family]

    distance = color_distance(
        wallpaper_color,
        hex_color,
    )

    return {
        "name": name,
        "color": hex_color,
        "distance": distance,
    }


def generate_xresources(theme, dwm_color):
    """Generate Xresources for DWM, dmenu, slock, and ST."""

    os.makedirs(
        os.path.dirname(XRESOURCES_PATH),
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

    for index, color in enumerate(terminal):
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

    for index, color in enumerate(terminal):
        lines.append(
            f"st.color{index}: {color}"
        )

    lines.extend([
        "",
        f"st.foreground: {theme['terminal_foreground']}",
        f"st.background: {theme['terminal_background']}",
        f"st.cursorColor: {theme['terminal_cursor']}",
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
        file.write("\n".join(lines))


def generate_dunst(theme, dwm_color):
    """Generate ~/.config/dunst/dunstrc."""

    os.makedirs(
        os.path.dirname(DUNST_PATH),
        exist_ok=True,
    )

    low_frame = theme["border"]
    normal_frame = dwm_color["color"]
    critical_frame = theme["dwm_colors"]["red"][1]

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
        file.write(content)


def print_usage():
    print(
        "Usage:\n"
        "  python wallpaper_colors.py WALLPAPER --theme THEME\n\n"
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
        choices=sorted(THEMES.keys()),
        help="Theme to use",
    )

    args = parser.parse_args()

    wallpaper = os.path.expanduser(
        args.wallpaper
    )

    theme_name = args.theme.lower()

    if not os.path.isfile(wallpaper):
        print(
            f"Error: file not found: {wallpaper}",
            file=sys.stderr,
        )
        return 1

    theme = THEMES[theme_name]

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

    dominant_family = analysis["dominant_family"]
    dominant_color = analysis["dominant_color"]

    dwm_color = find_dwm_color(
        theme,
        dominant_family,
        dominant_color,
    )

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
        f"Dominant family:    "
        f"{dominant_family}"
    )

    print(
        f"Occurrence:         "
        f"{analysis['dominant_percentage']:.2f}%"
    )

    print(
        f"Wallpaper color:    "
        f"{dominant_color}"
    )

    print(
        f"DWM theme color:    "
        f"{dwm_color['name']} "
        f"{dwm_color['color']}"
    )

    print(
        f"OKLab distance:     "
        f"{dwm_color['distance']:.4f}"
    )

    print()
    print("Family breakdown:")

    for family, percentage in sorted(
        analysis["family_percentages"].items(),
        key=lambda item: item[1],
        reverse=True,
    ):
        average = (
            analysis["family_average_colors"][family]
        )

        print(
            f"  {family:<8} "
            f"{percentage:>6.2f}%  "
            f"{average}"
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
