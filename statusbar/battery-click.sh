#!/bin/sh

BATTERY="/sys/class/power_supply/BAT1"

percent=$(cat "$BATTERY/capacity" 2>/dev/null || echo 0)
status=$(cat "$BATTERY/status" 2>/dev/null || echo Unknown)

if [ "$status" = "Charging" ]; then
    text="$percent% (Charging)"
else
    text="$percent%"
fi

notify-send \
    --app-name="Battery" \
    --expire-time=1500 \
    --hint=string:x-canonical-private-synchronous:battery \
    "Battery" \
    "$text"
