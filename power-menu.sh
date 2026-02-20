#!/bin/bash

CHOICE=$(printf "Suspend\nReboot\nPoweroff" | dmenu -i -p "Power Menu:")

case "$CHOICE" in
Suspend)
	sleep 2
	loginctl suspend
	;;
Reboot)
	loginctl reboot
	;;
Poweroff)
	loginctl poweroff
	;;
*)
	exit 0
	;;
esac
