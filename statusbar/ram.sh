#!/bin/sh

read total free buffers cached shmem sreclaimable <<EOF
$(awk '
/MemTotal:/      {t=$2}
/MemFree:/       {f=$2}
/Buffers:/       {b=$2}
/^Cached:/       {c=$2}
/Shmem:/         {s=$2}
/SReclaimable:/  {r=$2}
END {print t, f, b, c, s, r}
' /proc/meminfo)
EOF

used_kb=$((total - free - buffers - cached - sreclaimable + shmem))
used_mb=$((used_kb / 1024))

printf "^b4^^c#1E1E2E^  %s MB ^d^\n" "$used_mb"

