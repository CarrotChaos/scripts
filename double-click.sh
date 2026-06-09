#!/bin/bash

DEVICE_ID=18

xinput test "$DEVICE_ID" | while read -r line; do
	case "$line" in
	*"button press   1"*)
		xdotool click --repeat 2 1
		;;
	esac
done
