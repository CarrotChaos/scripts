#!/bin/sh

sink=$(pactl get-default-sink)
muted=$(pactl get-sink-mute "$sink" | awk '{print $2}')

if [ "$muted" = "yes" ]; then
	vol=0
	icon=""
else
	vol=$(pactl get-sink-volume "$sink" | grep -o '[0-9]\+%' | head -n1 | tr -d '%')

	# Safety: if parsing failed, treat as 0
	[ -z "$vol" ] && vol=0

	if [ "$vol" -le 30 ]; then
		icon=""
	elif [ "$vol" -le 70 ]; then
		icon=""
	else
		icon=""
	fi
fi

printf "%s %d%%\n" "$icon" "$vol"
