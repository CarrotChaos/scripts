#!/bin/sh

# Start autostart programs
~/scripts/autostart.sh &

file=/tmp/dwl-info
tmp=/tmp/dwl-info.tmp

: > "$file"

while IFS= read -r line; do
    printf '%s\n' "$line" >> "$file"

    # Keep the file below ~100 lines.
    lines=$(wc -l < "$file")

    if [ "$lines" -gt 70 ]; then
        tail -n 7 "$file" > "$tmp"
        cat "$tmp" > "$file"
        rm -f "$tmp"
    fi
done
