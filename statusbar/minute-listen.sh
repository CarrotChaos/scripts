#!/bin/sh
# minute-listener.sh - accurate, low-CPU, minute-aligned updater
# Run: ./minute-listener.sh &
SIGNAL=1

while true; do
    now=$(date +%s.%N)

    sec_int=${now%.*}     # integer seconds (string)
    ns=${now#*.}          # nanoseconds (string, 000000000–999999999)

    # Compute seconds_mod using POSIX-safe math
    seconds_mod=$(printf "%d" "$((sec_int % 60))")

    # If nanoseconds == 0 → we're exactly on a second
    if [ "$ns" = "000000000" ]; then
        int_sleep=$((60 - seconds_mod))
        frac_sleep="000000000"
    else
        int_sleep=$((59 - seconds_mod))

        # Calculate 1e9 - ns using printf instead of shell arithmetic
        frac_sleep=$(printf "%09d" $((1000000000 - 10#$ns)))
    fi

    # Final sleep time as INT.NNNNNNNNN (sleep supports floats)
    sleep_time=$(printf "%d.%s" "$int_sleep" "$frac_sleep")

    sleep "$sleep_time"

    pkill -RTMIN+"$SIGNAL" dwmblocks
done

