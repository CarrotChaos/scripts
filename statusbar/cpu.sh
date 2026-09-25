#!/bin/sh

# Show the notification immediately.
notify-send \
	--app-name="CPU" \
	--expire-time=5000 \
	--hint=string:x-canonical-private-synchronous:cpu \
	"CPU" \
	"Calculating..."

# First CPU sample.
read cpu user nice system idle iowait irq softirq steal guest guest_nice </proc/stat

prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
prev_idle=$idle

sleep 1

# Second CPU sample.
read cpu user nice system idle iowait irq softirq steal guest guest_nice </proc/stat

total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle2=$idle

diff_total=$((total - prev_total))
diff_idle=$((idle2 - prev_idle))

if [ "$diff_total" -gt 0 ]; then
	usage=$((100 * (diff_total - diff_idle) / diff_total))
else
	usage=0
fi

# Replace "Calculating..." with the result.
notify-send \
	--app-name="CPU" \
	--expire-time=5000 \
	--hint=string:x-canonical-private-synchronous:cpu \
	"CPU" \
	"$usage%"
