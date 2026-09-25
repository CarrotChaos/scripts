#!/bin/bash

CHOICE=$(printf "Suspend\nReboot\nPoweroff\nLock" | tofi)

case "$CHOICE" in
    Suspend)
        wlock &
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
