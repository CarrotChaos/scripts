#!/bin/sh

until pactl info >/dev/null 2>&1; do
    sleep 1
done

print_audio() {
    sink=$(pactl get-default-sink)
    muted=$(pactl get-sink-mute "$sink" | awk '{print $2}')

    if [ "$muted" = "yes" ]; then
        icon=""
    else
        vol=$(pactl get-sink-volume "$sink" |
            grep -o '[0-9]\+%' |
            head -n1 |
            tr -d '%')

        [ -z "$vol" ] && vol=0

        if [ "$vol" -le 30 ]; then
            icon=""
        elif [ "$vol" -le 70 ]; then
            icon=""
        else
            icon=""
        fi
    fi

    printf 'icon|string|%s\n' "$icon"
    printf '\n'
}

# Initial state
print_audio

# Update only when Pulse/PipeWire reports an audio change
pactl subscribe | while IFS= read -r event; do
    case "$event" in
        *"Event 'change' on sink"*|\
        *"Event 'new' on sink"*|\
        *"Event 'remove' on sink"*|\
        *"Event 'change' on server"*)
            print_audio
            ;;
    esac
done
