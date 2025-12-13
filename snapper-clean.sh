#!/bin/bash
# Snapper pre/post cleanup script
# Keeps only the newest 20 single snapshots (pre/post pacman)

CONFIG="root"
KEEP=15

# Get list of single snapshots, oldest first, numeric only, skip 0
SNAPS=$(snapper -c "$CONFIG" list | awk '/single/ {print $1}' | grep -E '^[1-9][0-9]*$' | sort -n)

# Count total snapshots
TOTAL=$(echo "$SNAPS" | wc -l)

# Calculate how many to delete
DELETE_COUNT=$((TOTAL - KEEP))

if [ "$DELETE_COUNT" -le 0 ]; then
  echo "Nothing to delete. Total snapshots: $TOTAL"
  exit 0
fi

# Delete the oldest snapshots
echo "$SNAPS" | head -n "$DELETE_COUNT" | while read SNAP; do
  echo "Deleting snapshot #$SNAP"
  snapper -c "$CONFIG" delete "$SNAP"
done
