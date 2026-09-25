#!/bin/sh

volume=$(pactl get-sink-volume @DEFAULT_SINK@ \
    | grep -o '[0-9]\+%' \
    | head -1)

mute=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')

if [ "$mute" = "yes" ]; then
    notify-send \
        --app-name="Volume" \
        --expire-time=1500 \
        --hint=string:x-canonical-private-synchronous:volume \
        "Volume" \
        "Muted"
else
    notify-send \
        --app-name="Volume" \
        --expire-time=1500 \
        --hint=string:x-canonical-private-synchronous:volume \
        "Volume" \
        "$volume"
fi
