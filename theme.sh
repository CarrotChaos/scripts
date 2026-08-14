#!/bin/sh

WALLPAPER="$(realpath "$1")"

~/theme-gen/theme-gen "$WALLPAPER"

mkdir -p ~/.cache/theme
printf '%s\n' "$WALLPAPER" >~/.cache/theme/wallpaper

xwallpaper --zoom "$WALLPAPER"

xrdb -merge ~/.cache/theme-gen/colors.Xresources

dunstctl reload
xdotool key super+F5
pkill -USR1 -x st
