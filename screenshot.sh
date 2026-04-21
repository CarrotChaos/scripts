#!/bin/bash

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"

FILENAME="$DIR/screenshot_$(date +'%Y-%m-%d_%H-%M-%S')"

CHOICE=$(printf "Full Screen\nSelect Area\nSelect QR Code\nSelect Area (5s delay)" | dmenu -i -p "Screenshot:")

case "$CHOICE" in
"Full Screen")
	sleep 0.08
	xnap -f | convert ppm:- "${FILENAME}.png" && sleep 0.08
	notify-send "Screenshot saved" "${FILENAME}.png"
	xclip -selection clipboard -t image/png -i "${FILENAME}.png"
	;;
"Select Area")
	sleep 0.08
	xnap | convert ppm:- "${FILENAME}.png" && notify-send "Screenshot saved" "${FILENAME}.png"
	xclip -selection clipboard -t image/png -i "${FILENAME}.png"
	;;
"Select QR Code")
	sleep 0.08
	xnap | zbarimg -q --raw - | xclip -selection clipboard && notify-send "Text copied to clipboard!"
	;;
"Select Area (5s delay)")
	sleep 5 && xnap -f >"$FILENAME" && notify-send "Screenshot saved" "$FILENAME"
	xclip -selection clipboard -t image/png -i "${FILENAME}.png"
	;;
*)
	exit 0
	;;
esac
