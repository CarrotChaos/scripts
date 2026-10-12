#!/bin/sh

BATTERY="/sys/class/power_supply/BAT1"

get_battery() {
    percent=$(cat "$BATTERY/capacity" 2>/dev/null || echo 0)
    status=$(cat "$BATTERY/status" 2>/dev/null || echo Unknown)

    if [ "$status" = "Charging" ]; then
        if [ "$percent" -ge 90 ]; then
            icon="󰂅"
        elif [ "$percent" -ge 80 ]; then
            icon="󰂋"
        elif [ "$percent" -ge 70 ]; then
            icon="󰂊"
        elif [ "$percent" -ge 60 ]; then
            icon="󰂉"
        elif [ "$percent" -ge 50 ]; then
            icon="󰂈"
        elif [ "$percent" -ge 40 ]; then
            icon="󰂇"
        elif [ "$percent" -ge 30 ]; then
            icon="󰂆"
        elif [ "$percent" -ge 20 ]; then
            icon="󰂃"
        else
            icon="󰂄"
        fi

    elif [ "$percent" -ge 90 ]; then
        icon="󰁹"
    elif [ "$percent" -ge 80 ]; then
        icon="󰂁"
    elif [ "$percent" -ge 70 ]; then
        icon="󰂀"
    elif [ "$percent" -ge 60 ]; then
        icon="󰁿"
    elif [ "$percent" -ge 50 ]; then
        icon="󰁾"
    elif [ "$percent" -ge 40 ]; then
        icon="󰁽"
    elif [ "$percent" -ge 30 ]; then
        icon="󰁼"
    elif [ "$percent" -ge 20 ]; then
        icon="󰁻"
    else
        icon="󰂎"
    fi

    printf 'icon|string|%s\n' "$icon"
    printf 'percent|int|%s\n' "$percent"
    printf '\n'
}

# Initial state
get_battery

# Wait for actual power-supply events
udevadm monitor --udev --subsystem-match=power_supply |
while IFS= read -r line; do
    case "$line" in
        *"change"*)
            get_battery
            ;;
    esac
done
