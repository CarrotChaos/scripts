#!/bin/sh

# Get active Wi-Fi connection
wifi_info=$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi | grep '^yes:')

ssid=$(echo "$wifi_info" | cut -d: -f2)
signal=$(echo "$wifi_info" | cut -d: -f3)

# No Wi-Fi connected
if [ -z "$ssid" ]; then
    echo "󰤭 Disconnected"
    exit 0
fi

# Choose icon based on signal strength
if [ "$signal" -ge 80 ]; then
    icon="󰤨"
elif [ "$signal" -ge 60 ]; then
    icon="󰤥"
elif [ "$signal" -ge 40 ]; then
    icon="󰤢"
elif [ "$signal" -ge 20 ]; then
    icon="󰤟"
else
    icon="󰤯"
fi

echo "$icon $ssid"
