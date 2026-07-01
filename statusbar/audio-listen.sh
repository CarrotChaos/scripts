#!/bin/sh

SIGNAL=10

# Wait for Pulse/PipeWire to be ready
until pactl info >/dev/null 2>&1; do
    sleep 1
done

# 🔑 IMPORTANT: trigger initial update so dwmblocks is correct at startup
pkill -RTMIN+"$SIGNAL" dwmblocks

# Subscribe to events (force line buffering just in case)
pactl subscribe | while IFS= read -r event; do
    case "$event" in
        *"Event 'change' on sink"*|\
        *"Event 'new' on sink"*|\
        *"Event 'remove' on sink"*|\
        *"Event 'change' on server"*)
            pkill -RTMIN+"$SIGNAL" dwmblocks
            ;;
    esac
done
