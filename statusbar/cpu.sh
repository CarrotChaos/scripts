#!/bin/sh

# Read /proc/stat values
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
prev_idle=$idle

sleep 1

read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle2=$idle

diff_total=$((total - prev_total))
diff_idle=$((idle2 - prev_idle))
usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))

printf "󰍛 %d%%\n" "$usage"

