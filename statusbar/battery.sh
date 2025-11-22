#!/bin/sh

# Get battery percentage
percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo "0")

# Get charging state
if grep -q "Charging" /sys/class/power_supply/BAT*/status 2>/dev/null; then
    charging=true
else
    charging=false
fi

# Choose icon depending on level
if [ "$charging" = true ]; then
    icon="󰂄"  # charging
elif [ "$percent" -ge 90 ]; then
    icon="󰁹"
elif [ "$percent" -ge 70 ]; then
    icon="󰂁"
elif [ "$percent" -ge 50 ]; then
    icon="󰁿"
elif [ "$percent" -ge 30 ]; then
    icon="󰁽"
elif [ "$percent" -ge 10 ]; then
    icon="󰁻"
else
    icon="󰂎"  # low
fi

printf "%s %s%%\n" "$icon" "$percent"

