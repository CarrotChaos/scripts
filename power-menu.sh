#!/bin/bash

CHOICE=$(printf "Suspend\nReboot\nPoweroff\nLock" | dmenu -i -p "Power Menu:")

case "$CHOICE" in
Suspend)
	slock &
	loginctl suspend
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
