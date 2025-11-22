#!/bin/sh

used_kb=$(awk '
    /Active\(anon\)/   {a=$2}
    /Inactive\(anon\)/ {i=$2}
    /SUnreclaim:/      {u=$2}
    /KernelStack:/     {k=$2}
    /PageTables:/      {p=$2}
    END {print a + i + u + k + p}
' /proc/meminfo)

used_mb=$((used_kb / 1024))

printf "  %s MB\n" "$used_mb"

