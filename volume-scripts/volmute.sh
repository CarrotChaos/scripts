#!/bin/sh

pactl set-sink-mute @DEFAULT_SINK@ toggle

mute=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')
volume=$(pactl get-sink-volume @DEFAULT_SINK@ \
    | grep -o '[0-9]\+%' \
    | head -1)

if [ "$mute" = "yes" ]; then
    text="Muted"
else
    text="$volume"
fi

notify-send \
    --app-name="Volume" \
    --expire-time=1500 \
    --hint=string:x-canonical-private-synchronous:volume \
    "Volume" \
    "$text"
