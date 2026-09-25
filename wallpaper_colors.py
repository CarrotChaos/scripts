#!/usr/bin/env python3

import argparse
import subprocess
from pathlib import Path


# Easily change the chosen/accent color for each theme here.
CHOSEN_COLORS = {
    "catppuccin": "cdd6f4",
    "gruvbox": "ebdbb2",
}


COLORSCHEMES = {
    "catppuccin": {
        "background": "1e1e2e",
        "foreground": "cdd6f4",
        "selection_background": "313244",

        "foot": """# _*_ conf _*_
# Catppuccin Mocha

[colors-dark]
alpha=0.98

foreground=cdd6f4
background=1e1e2e

regular0=45475a
regular1=f38ba8
regular2=a6e3a1
regular3=f9e2af
regular4=89b4fa
regular5=f5c2e7
regular6=94e2d5
regular7=bac2de

bright0=585b70
bright1=f38ba8
bright2=a6e3a1
bright3=f9e2af
bright4=89b4fa
bright5=f5c2e7
bright6=94e2d5
bright7=a6adc8

cursor=11111b f5e0dc

16=fab387
17=f5e0dc

selection-foreground=cdd6f4
selection-background=414356

search-box-no-match=11111b f38ba8
search-box-match=cdd6f4 313244

jump-labels=11111b fab387
urls=89b4fa
""",
    },

    "gruvbox": {
        "background": "282828",
        "foreground": "ebdbb2",
        "selection_background": "504945",

        "foot": """# -*- conf -*-
# Gruvbox

[colors-dark]
alpha=0.98

background=282828
foreground=ebdbb2

bright0=928374
bright1=fb4934
bright2=b8bb26
bright3=fabd2f
bright4=83a598
bright5=d3869b
bright6=8ec07c
bright7=ebdbb2
""",
    },
}


def create_color_files(theme, image_path):
    colors = COLORSCHEMES[theme]

    cache_dir = Path.home() / ".cache" / "colors"
    cache_dir.mkdir(parents=True, exist_ok=True)

    background = colors["background"]
    foreground = colors["foreground"]
    selection_background = colors["selection_background"]

    # The chosen color is configured at the top of the script.
    chosen_color = CHOSEN_COLORS[theme]

    # dwl
    (cache_dir / "dwl").write_text(
        f"{chosen_color}ff\n",
        encoding="utf-8",
    )

    # foot
    (cache_dir / "foot").write_text(
        colors["foot"],
        encoding="utf-8",
    )

    # maybar
    (cache_dir / "maybar").write_text(
        f"export background={background}ff\n"
        f"export foreground={foreground}ff\n",
        encoding="utf-8",
    )

    # tofi
    (cache_dir / "tofi").write_text(
        f"background-color = #{background}\n"
        f"text-color = #{foreground}\n"
        f"selection-color = #{chosen_color}\n"
        f"selection-background = #{selection_background}\n"
        f"border-color = #{chosen_color}\n",
        encoding="utf-8",
    )

    # wallpaper
    (cache_dir / "wallpaper").write_text(
        str(image_path.resolve()) + "\n",
        encoding="utf-8",
    )


def reload_desktop(image_path):
    start_maybar = Path.home() / "scripts" / "start-maybar.sh"

    # Reload dwl
    subprocess.run(
        ["pkill", "-USR1", "-x", "dwl"],
        check=False,
    )

    # Stop existing maybar
    subprocess.run(
        ["pkill", "-x", "maybar"],
        check=False,
    )

    # Stop existing wallpaper
    subprocess.run(
        ["pkill", "-x", "swaybg"],
        check=False,
    )

    # Start maybar detached
    subprocess.Popen(
        [str(start_maybar)],
        start_new_session=True,
    )

    # Set wallpaper with swaybg using fill
    subprocess.Popen(
        [
            "swaybg",
            "-m",
            "fill",
            "-i",
            str(image_path.resolve()),
        ],
        start_new_session=True,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Set the desktop theme and wallpaper."
    )

    parser.add_argument(
        "image",
        help="Path to wallpaper image",
    )

    parser.add_argument(
        "--theme",
        required=True,
        choices=["catppuccin", "gruvbox"],
        help="Color scheme to use",
    )

    args = parser.parse_args()

    image_path = Path(args.image).expanduser()

    if not image_path.is_file():
        parser.error(f"Image not found: {image_path}")

    colors = COLORSCHEMES[args.theme]
    chosen_color = CHOSEN_COLORS[args.theme]

    print(f"Theme:             {args.theme}")
    print(f"Chosen color:      #{chosen_color}")
    print(f"Wallpaper:         {image_path.resolve()}")

    create_color_files(
        args.theme,
        image_path,
    )

    reload_desktop(image_path)


if __name__ == "__main__":
    main()
