#!/bin/bash

CHOICE=$(printf "Suspend\nReboot\nPoweroff\nLock" | dmenu -i -p "Power Menu:")

case "$CHOICE" in
Suspend)
	slock &
	sleep 1
	loginctl suspend
	xset dpms force on
	;;
Reboot)
	loginctl reboot
	;;
Poweroff)
	loginctl poweroff
	;;
Lock)
	slock &
	;;
*)
	exit 0
	;;
esac
