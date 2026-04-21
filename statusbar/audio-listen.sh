#!/bin/sh
# audio-listen.sh - Background listener to signal dwmblocks on audio changes
# Run this as: volume-listener.sh &
# Adjust the signal number to match your config.h (e.g., RTMIN+10 for signal 10).

SIGNAL=10  # Match this to your block's update signal in config.h

pactl subscribe | while read -r event; do
    if echo "$event" | grep -qE "'change' on (sink|server)" || echo "$event" | grep -qE "'(new|remove)' on sink"; then
        pkill -RTMIN+"$SIGNAL" dwmblocks
    fi
done
