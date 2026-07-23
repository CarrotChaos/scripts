#!/usr/bin/env bash
set -euo pipefail

INPUT="$HOME/passwords.json.gpg"
OUTPUT="/dev/shm/passwords.json"

if [ ! -f "$INPUT" ]; then
	echo "Error: $INPUT not found."
	exit 1
fi

rm -f "$OUTPUT"

echo "Decrypting..."

gpg \
	--output "$OUTPUT" \
	--decrypt "$INPUT"

echo
echo "Passwords available at:"
echo "$OUTPUT"
