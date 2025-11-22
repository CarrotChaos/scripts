#!/bin/bash

CHOICE=$(printf "Suspend\nReboot\nPoweroff" | dmenu -i -p "Power Menu:")

case "$CHOICE" in
    Suspend)
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

