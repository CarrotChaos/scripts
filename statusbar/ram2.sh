#!/bin/sh

used_kb=$(awk '
    /MemTotal:/     {t=$2}
    /MemAvailable:/ {a=$2}
    END {print t - a}
' /proc/meminfo)

used_mb=$((used_kb / 1024))

printf " %s MB\n" "$used_mb"
