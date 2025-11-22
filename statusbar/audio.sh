#!/bin/sh
# volume.sh - Block command script for dwmblocks-async
# Place this script in a suitable location, e.g., ~/.local/bin/volume.sh
# In config.h, add a block like: X("", "volume.sh", 0, 10)
# The signal 10 can be whatever positive integer you choose, as long as it's unique.

sink=$(pactl get-default-sink)
muted=$(pactl get-sink-mute "$sink" | awk '{print $2}')
if [ "$muted" = "yes" ]; then
    vol=0
    icon=""
else
    vol=$(pactl get-sink-volume "$sink" | grep -oP 'Volume:.*?/\s*\K\d+(?=%)' | head -n1)
    if [ "$vol" -eq 0 ]; then
        icon=""
    elif [ "$vol" -le 30 ]; then
        icon=""
    elif [ "$vol" -le 70 ]; then
        icon=""
    else
        icon=""
    fi
fi
# printf "%s %d%%\n" "$icon" "$vol"
printf "%s  %d%%\n" "$icon" "$vol"

