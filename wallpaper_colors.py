#!/usr/bin/env python3

from PIL import Image
from collections import defaultdict
import colorsys
import math
import os
import sys


# ============================================================
# CONFIGURATION
# ============================================================

ANALYSIS_SIZE = 500

BLACK_THRESHOLD = 0.10
WHITE_THRESHOLD = 0.92
MIN_SATURATION = 0.12


# ============================================================
# COLORSCHEMES
# ============================================================

THEMES = {

    # --------------------------------------------------------
    # CATPPUCCIN MOCHA
    # --------------------------------------------------------

    "catppuccin": {
        "display_name": "Catppuccin Mocha",

        "background": "#1e1e2e",
        "foreground": "#cdd6f4",

        # Normal dwm border.
        "border": "#585b70",

        "background_sel": "#313244",

        "colors": {
            "Rosewater": ("#f5e0e6", "red"),
            "Flamingo": ("#f2cdcd", "red"),

            "Pink": ("#f5c2e7", "purple"),
            "Mauve": ("#cba6f7", "purple"),

            "Red": ("#f38ba8", "red"),
            "Maroon": ("#eba0ac", "red"),

            "Peach": ("#fab387", "yellow"),
            "Yellow": ("#f9e2af", "yellow"),

            "Green": ("#a6e3a1", "green"),

            "Teal": ("#94e2d5", "cyan"),
            "Sky": ("#89dceb", "cyan"),

            "Sapphire": ("#74c7ec", "blue"),
            "Blue": ("#89b4fa", "blue"),

            "Lavender": ("#b4befe", "purple"),
        },
    },


    # --------------------------------------------------------
    # DRACULA
    # --------------------------------------------------------

    "dracula": {
        "display_name": "Dracula",

        "background": "#282a36",
        "foreground": "#f8f8f2",

        # Normal dwm border.
        "border": "#6272a4",

        "background_sel": "#44475a",

        "colors": {
            "Red": ("#ff5555", "red"),
            "Orange": ("#ffb86c", "yellow"),
            "Yellow": ("#f1fa8c", "yellow"),
            "Green": ("#50fa7b", "green"),
            "Cyan": ("#8be9fd", "cyan"),
            "Purple": ("#bd93f9", "purple"),
            "Pink": ("#ff79c6", "purple"),
        },
    },


    # --------------------------------------------------------
    # GRUVBOX DARK
    #
    # Only bright/accent colors are considered for matching.
    # Dark Gruvbox colors are intentionally not candidates.
    # --------------------------------------------------------

    "gruvbox": {
        "display_name": "Gruvbox Dark",

        "background": "#282828",
        "foreground": "#ebdbb2",

        # Normal dwm border.
        "border": "#665c54",

        "background_sel": "#3c3836",

        "colors": {
            "Bright Red": ("#fb4934", "red"),
            "Bright Green": ("#b8bb26", "green"),
            "Bright Yellow": ("#fabd2f", "yellow"),
            "Bright Blue": ("#83a598", "blue"),
            "Bright Purple": ("#d3869b", "purple"),
            "Bright Aqua": ("#8ec07c", "cyan"),
        },
    },
}


# ============================================================
# HEX -> RGB
# ============================================================

def hex_to_rgb(hex_color):

    hex_color = hex_color.lstrip("#")

    return tuple(
        int(hex_color[i:i + 2], 16)
        for i in (0, 2, 4)
    )


# ============================================================
# RGB -> OKLAB
# ============================================================

def rgb_to_oklab(r, g, b):

    r /= 255.0
    g /= 255.0
    b /= 255.0

    def linearize(c):

        if c <= 0.04045:
            return c / 12.92

        return ((c + 0.055) / 1.055) ** 2.4

    r = linearize(r)
    g = linearize(g)
    b = linearize(b)

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

    l = l ** (1 / 3)
    m = m ** (1 / 3)
    s = s ** (1 / 3)

    L = (
        0.2104542553 * l
        + 0.7936177850 * m
        - 0.0040720468 * s
    )

    A = (
        1.9779984951 * l
        - 2.4285922050 * m
        + 0.4505937099 * s
    )

    B = (
        0.0259040371 * l
        + 0.7827717662 * m
        - 0.8086757660 * s
    )

    return L, A, B


# ============================================================
# OKLAB COLOR DISTANCE
# ============================================================

def color_distance(c1, c2):

    return math.sqrt(
        (c1[0] - c2[0]) ** 2
        + (c1[1] - c2[1]) ** 2
        + (c1[2] - c2[2]) ** 2
    )


# ============================================================
# SATURATION
# ============================================================

def get_saturation(r, g, b):

    r /= 255.0
    g /= 255.0
    b /= 255.0

    maximum = max(r, g, b)
    minimum = min(r, g, b)

    if maximum == 0:
        return 0

    return (maximum - minimum) / maximum


# ============================================================
# IGNORE BLACK / WHITE / GRAY
# ============================================================

def should_ignore(r, g, b):

    brightness = max(
        r / 255.0,
        g / 255.0,
        b / 255.0
    )

    saturation = get_saturation(
        r,
        g,
        b
    )

    # Black.
    if brightness < BLACK_THRESHOLD:
        return True

    # White / very light gray.
    if (
        brightness > WHITE_THRESHOLD
        and saturation < 0.25
    ):
        return True

    # Gray.
    if saturation < MIN_SATURATION:
        return True

    return False


# ============================================================
# COLOR FAMILY
# ============================================================

def classify_family(r, g, b):

    r /= 255.0
    g /= 255.0
    b /= 255.0

    h, s, v = colorsys.rgb_to_hsv(
        r,
        g,
        b
    )

    hue = h * 360

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


# ============================================================
# ANALYZE WALLPAPER
# ============================================================

def analyze_wallpaper(filename):

    image = Image.open(
        filename
    ).convert("RGB")

    image.thumbnail(
        (
            ANALYSIS_SIZE,
            ANALYSIS_SIZE
        )
    )

    family_pixels = defaultdict(list)

    ignored = 0

    # Pillow 14 compatible.
    #
    # Do NOT change this back to image.getdata().
    pixels = image.get_flattened_data()

    for r, g, b in pixels:

        if should_ignore(
            r,
            g,
            b
        ):
            ignored += 1
            continue

        family = classify_family(
            r,
            g,
            b
        )

        family_pixels[family].append(
            (r, g, b)
        )

    total_colored = sum(
        len(pixels)
        for pixels in family_pixels.values()
    )

    if total_colored == 0:
        return None

    results = []

    for family, pixels in family_pixels.items():

        avg_r = (
            sum(p[0] for p in pixels)
            / len(pixels)
        )

        avg_g = (
            sum(p[1] for p in pixels)
            / len(pixels)
        )

        avg_b = (
            sum(p[2] for p in pixels)
            / len(pixels)
        )

        avg_rgb = (
            round(avg_r),
            round(avg_g),
            round(avg_b)
        )

        avg_lab = rgb_to_oklab(
            avg_r,
            avg_g,
            avg_b
        )

        percentage = (
            len(pixels)
            / total_colored
        ) * 100

        results.append({
            "family": family,
            "percentage": percentage,
            "rgb": avg_rgb,
            "lab": avg_lab,
        })

    results.sort(
        key=lambda x: x["percentage"],
        reverse=True
    )

    return {
        "families": results,
        "ignored": ignored,
        "colored": total_colored,
    }


# ============================================================
# FIND CLOSEST THEME COLOR
# ============================================================

def find_closest_theme_color(
    wallpaper_lab,
    family,
    theme
):

    best_name = None
    best_hex = None
    best_distance = float("inf")

    for (
        name,
        (
            hex_color,
            color_family
        )
    ) in theme["colors"].items():

        # Only compare colors from the same family.
        if color_family != family:
            continue

        theme_rgb = hex_to_rgb(
            hex_color
        )

        theme_lab = rgb_to_oklab(
            *theme_rgb
        )

        distance = color_distance(
            wallpaper_lab,
            theme_lab
        )

        if distance < best_distance:

            best_distance = distance
            best_name = name
            best_hex = hex_color

    return (
        best_name,
        best_hex,
        best_distance
    )


# ============================================================
# FIND THEME COLOR BY FAMILY
# ============================================================

def find_theme_color(
    theme,
    family
):

    for (
        name,
        (
            hex_color,
            color_family
        )
    ) in theme["colors"].items():

        if color_family == family:
            return (
                name,
                hex_color
            )

    return (
        None,
        None
    )


# ============================================================
# GENERATE COLORS.XRESOURCES
#
# Contains:
#
#   dwm
#   dmenu
#   slock
#
# ============================================================

def generate_xresources(
    filename,
    theme,
    primary
):

    primary_name = primary["theme_name"]
    primary_hex = primary["theme_hex"]

    background = theme["background"]
    foreground = theme["foreground"]
    background_sel = theme["background_sel"]

    # --------------------------------------------------------
    # IMPORTANT:
    #
    # Normal dwm border is the theme's neutral border.
    #
    # It is NOT the wallpaper-matched accent.
    # --------------------------------------------------------

    border = theme["border"]

    # --------------------------------------------------------
    # slock colors
    #
    # Your slock patch expects:
    #
    # slock.color0 -> INIT
    # slock.color4 -> INPUT
    # slock.color1 -> FAILED
    # slock.color3 -> CAPS
    # --------------------------------------------------------

    (
        red_name,
        red_hex
    ) = find_theme_color(
        theme,
        "red"
    )

    (
        yellow_name,
        yellow_hex
    ) = find_theme_color(
        theme,
        "yellow"
    )

    if red_hex is None:
        red_hex = primary_hex

    if yellow_hex is None:
        yellow_hex = primary_hex

    output = f"""! generated by theme-gen
! theme: {theme["display_name"]}
! wallpaper: {os.path.basename(filename)}
! dominant wallpaper color: {primary["family"]}
! matched theme color: {primary_name} {primary_hex}


! ============================================================
! dwm
! ============================================================

dwm.background: {background}
dwm.foreground: {foreground}
dwm.border: {border}

dwm.backgroundSel: {primary_hex}
dwm.foregroundSel: {background}
dwm.borderSel: {primary_hex}


! ============================================================
! dmenu
! ============================================================

dmenu.background:    {background}
dmenu.foreground:    {foreground}

dmenu.backgroundSel: {primary_hex}
dmenu.foregroundSel: {background}

dmenu.backgroundOut: {background_sel}
dmenu.foregroundOut: {foreground}


! ============================================================
! slock
!
! slock Xresources patch:
!
! color0 -> INIT
! color4 -> INPUT
! color1 -> FAILED
! color3 -> CAPS
! ============================================================

slock.color0: {background}
slock.color4: {primary_hex}
slock.color1: {red_hex}
slock.color3: {yellow_hex}
"""

    output_dir = os.path.expanduser(
        "~/.cache/theme-gen"
    )

    os.makedirs(
        output_dir,
        exist_ok=True
    )

    output_file = os.path.join(
        output_dir,
        "colors.Xresources"
    )

    with open(
        output_file,
        "w"
    ) as f:

        f.write(output)

    return output_file


# ============================================================
# GENERATE DUNST
# ============================================================

def generate_dunst(
    theme,
    primary
):

    background = theme["background"]
    foreground = theme["foreground"]
    background_sel = theme["background_sel"]

    # Normal notification uses the actual matched
    # colorscheme color.
    normal_color = primary["theme_hex"]

    # Critical notification uses the colorscheme red.
    (
        red_name,
        critical_color
    ) = find_theme_color(
        theme,
        "red"
    )

    if critical_color is None:
        critical_color = normal_color

    output = f"""# generated by theme-gen
# theme: {theme["display_name"]}

[global]
font = JetBrains Mono 10
frame_width = 3
corner_radius = 0
separator_height = 2

[urgency_low]
background = "{background}"
foreground = "{foreground}"
frame_color = "{background_sel}"

[urgency_normal]
background = "{background}"
foreground = "{foreground}"
frame_color = "{normal_color}"

[urgency_critical]
background = "{background}"
foreground = "{foreground}"
frame_color = "{critical_color}"
"""

    output_dir = os.path.expanduser(
        "~/.config/dunst"
    )

    os.makedirs(
        output_dir,
        exist_ok=True
    )

    output_file = os.path.join(
        output_dir,
        "dunstrc"
    )

    with open(
        output_file,
        "w"
    ) as f:

        f.write(output)

    return output_file


# ============================================================
# USAGE
# ============================================================

def print_usage():

    print()
    print("Usage:")
    print()
    print(
        "  python wallpaper_colors.py "
        "WALLPAPER --theme THEME"
    )
    print()
    print("Available themes:")

    for key, theme in THEMES.items():

        print(
            f"  {key:<12}"
            f"{theme['display_name']}"
        )

    print()


# ============================================================
# MAIN
# ============================================================

def main():

    if len(sys.argv) < 2:

        print_usage()
        sys.exit(1)

    filename = sys.argv[1]

    # Default theme.
    theme_name = "catppuccin"

    # --------------------------------------------------------
    # Parse --theme
    # --------------------------------------------------------

    if "--theme" in sys.argv:

        index = sys.argv.index(
            "--theme"
        )

        if index + 1 >= len(sys.argv):

            print(
                "Error: --theme requires "
                "a theme name."
            )

            print_usage()
            sys.exit(1)

        theme_name = sys.argv[
            index + 1
        ]

    # --------------------------------------------------------
    # Validate theme
    # --------------------------------------------------------

    if theme_name not in THEMES:

        print()

        print(
            f"Error: unknown theme "
            f"'{theme_name}'"
        )

        print_usage()
        sys.exit(1)

    theme = THEMES[theme_name]

    # --------------------------------------------------------
    # Analyze wallpaper
    # --------------------------------------------------------

    try:

        result = analyze_wallpaper(
            filename
        )

    except FileNotFoundError:

        print(
            f"Error: file not found: "
            f"{filename}"
        )

        sys.exit(1)

    except Exception as e:

        print(
            f"Error analyzing wallpaper: "
            f"{e}"
        )

        sys.exit(1)

    if result is None:

        print(
            "No sufficiently colorful "
            "pixels were found."
        )

        sys.exit(1)

    # --------------------------------------------------------
    # Find dominant family
    # --------------------------------------------------------

    primary = result["families"][0]

    (
        theme_color_name,
        theme_hex,
        distance
    ) = find_closest_theme_color(
        primary["lab"],
        primary["family"],
        theme
    )

    # --------------------------------------------------------
    # If the dominant family doesn't exist in the selected
    # theme, try the next most dominant family.
    # --------------------------------------------------------

    if theme_hex is None:

        for candidate in result["families"][1:]:

            (
                candidate_name,
                candidate_hex,
                candidate_distance
            ) = find_closest_theme_color(
                candidate["lab"],
                candidate["family"],
                theme
            )

            if candidate_hex is not None:

                primary = candidate

                theme_color_name = (
                    candidate_name
                )

                theme_hex = (
                    candidate_hex
                )

                distance = (
                    candidate_distance
                )

                break

    if theme_hex is None:

        print(
            "Error: no matching color "
            "could be found in the selected "
            "colorscheme."
        )

        sys.exit(1)

    primary["theme_name"] = (
        theme_color_name
    )

    primary["theme_hex"] = (
        theme_hex
    )

    # --------------------------------------------------------
    # Generate files
    # --------------------------------------------------------

    xresources_file = generate_xresources(
        filename,
        theme,
        primary
    )

    dunst_file = generate_dunst(
        theme,
        primary
    )

    # --------------------------------------------------------
    # Critical red
    # --------------------------------------------------------

    (
        critical_name,
        critical_hex
    ) = find_theme_color(
        theme,
        "red"
    )

    # --------------------------------------------------------
    # Output
    # --------------------------------------------------------

    print()

    print("=" * 65)
    print("                    THEME-GEN")
    print("=" * 65)

    print()

    print(
        f"THEME           → "
        f"{theme['display_name']}"
    )

    print(
        f"DOMINANT COLOR  → "
        f"{primary['family'].upper()}"
    )

    print(
        f"OCCURRENCE      → "
        f"{primary['percentage']:.2f}%"
    )

    r, g, b = primary["rgb"]

    print(
        f"WALLPAPER COLOR → "
        f"#{r:02x}{g:02x}{b:02x}"
    )

    print(
        f"THEME MATCH     → "
        f"{theme_color_name}"
    )

    print(
        f"NORMAL DUNST    → "
        f"{theme_hex}"
    )

    print(
        f"CRITICAL DUNST  → "
        f"{critical_name} "
        f"{critical_hex}"
    )

    print()

    print(
        f"BACKGROUND      → "
        f"{theme['background']}"
    )

    print(
        f"FOREGROUND      → "
        f"{theme['foreground']}"
    )

    print(
        f"NORMAL BORDER   → "
        f"{theme['border']}"
    )

    print()

    print(
        f"IGNORED         → "
        f"{result['ignored']} pixels"
    )

    print()

    print("Generated files:")

    print(
        f"  Xresources → "
        f"{xresources_file}"
    )

    print(
        f"  Dunst      → "
        f"{dunst_file}"
    )

    print()


# ============================================================
# RUN
# ============================================================

if __name__ == "__main__":
    main()
