#!/bin/bash

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"

FILENAME="$DIR/screenshot_$(date +'%Y-%m-%d_%H-%M-%S').png"

CHOICE=$(printf "Full Screen\nSelect Area\nActive Window\nDelay 5s" | dmenu -i -p "Screenshot:")

case "$CHOICE" in
    "Full Screen")
        scrot "$FILENAME" && notify-send "Screenshot saved" "$FILENAME" 
        ;;
    "Select Area")
	sleep 0.08
	scrot -s -f "$FILENAME" && notify-send "Screenshot saved" "$FILENAME" 
        ;;
    "Active Window")
        scrot -u "$FILENAME" && notify-send "Screenshot saved" "$FILENAME" 
        ;;
    "Delay 5s")
        sleep 5 && scrot "$FILENAME" && notify-send "Screenshot saved" "$FILENAME" 
        ;;
    *)
        exit 0
        ;;
esac

