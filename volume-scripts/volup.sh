#!/bin/sh

pactl set-sink-volume @DEFAULT_SINK@ +1%

volume=$(pactl get-sink-volume @DEFAULT_SINK@ \
    | grep -o '[0-9]\+%' \
    | head -1)

notify-send \
    --app-name="Volume" \
    --expire-time=1500 \
    --hint=string:x-canonical-private-synchronous:volume \
    "Volume" \
    "$volume"
