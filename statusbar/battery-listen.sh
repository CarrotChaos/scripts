#!/bin/sh

# Change this to match your block's signal number
SIGNAL=6

# Function to signal dwmblocks
signal_dwmblocks() {
	pkill -RTMIN+$SIGNAL dwmblocks
}

# Trigger once at startup
signal_dwmblocks

# Listen for battery events
udevadm monitor --udev --subsystem-match=power_supply | while read -r line; do
	case "$line" in
	*"change"*)
		signal_dwmblocks
		;;
	esac
done
