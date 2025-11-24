#!/bin/bash

HISTFILE="$HOME/.cache/mount_points"
mkdir -p "$(dirname "$HISTFILE")"
touch "$HISTFILE"

# Ask whether user wants mount or unmount
ACTION=$(printf "Mount\nUnmount" | dmenu -i -p "Action:")
[ -z "$ACTION" ] && exit 0

# ----------------------------------------
# MOUNT MODE
# ----------------------------------------
if [ "$ACTION" = "Mount" ]; then

    # List unused partitions
    DRIVE=$(lsblk -rpno NAME,SIZE,TYPE,MOUNTPOINT | \
            awk '$3=="part" && $4=="" {print $1" ("$2")"}' | \
            dmenu -i -p "Select drive to mount:")
    [ -z "$DRIVE" ] && exit 0

    DEV=$(echo "$DRIVE" | awk '{print $1}')

    # Choose from history or "Other"
    MOUNTPOINT=$( (cat "$HISTFILE"; echo "Other…") | dmenu -i -p "Mount where?")
    [ -z "$MOUNTPOINT" ] && exit 0

    if [ "$MOUNTPOINT" = "Other…" ]; then
        MOUNTPOINT=$(dmenu -p "Enter mount path:" < /dev/null)
        [ -z "$MOUNTPOINT" ] && exit 0
    fi

    # Create directory if missing
    if [ ! -d "$MOUNTPOINT" ]; then
        CONFIRM=$(printf "No\nYes" | dmenu -i -p "$MOUNTPOINT does not exist. Create?")
        [ "$CONFIRM" = "Yes" ] || exit 0
        pkexec mkdir -p "$MOUNTPOINT" || exit 1
    fi

    # Mount using pkexec
    if pkexec mount "$DEV" "$MOUNTPOINT"; then
        notify-send "Mounted" "$DEV → $MOUNTPOINT"

        # Save mount point to history
        if ! grep -Fxq "$MOUNTPOINT" "$HISTFILE"; then
            echo "$MOUNTPOINT" >> "$HISTFILE"
        fi
    else
        notify-send "Mount failed" "$DEV"
    fi

    exit 0
fi

# ----------------------------------------
# UNMOUNT MODE
# ----------------------------------------
if [ "$ACTION" = "Unmount" ]; then

    # List mounted external drives
    DRIVE=$(lsblk -rpno NAME,MOUNTPOINT,TYPE | \
            awk '$3=="part" && $2!="" {print $1" → "$2}' | \
            dmenu -i -p "Select drive to unmount:")
    [ -z "$DRIVE" ] && exit 0

    DEV=$(echo "$DRIVE" | awk '{print $1}')

    if pkexec umount "$DEV"; then
        notify-send "Unmounted" "$DEV"
    else
        notify-send "Unmount failed" "$DEV"
    fi

    exit 0
fi

