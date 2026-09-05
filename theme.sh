#!/bin/sh

WALLPAPER="$(realpath "$1")"
THEME="$2"


python ~/scripts/wallpaper_colors.py "$WALLPAPER" --theme "$THEME" && xwallpaper --zoom "$WALLPAPER" && printf '%s\n' "$WALLPAPER" > ~/.cache/wallpaper && xrdb -merge ~/.cache/theme-gen/colors.Xresources && dunstctl reload && xdotool key super+F5 && pkill -USR1 -x st

