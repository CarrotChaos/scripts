#!/usr/bin/env bash
set -euo pipefail

KEYID="user@gentoo.org"

INPUT="/dev/shm/passwords.json"
OUTPUT="$HOME/passwords.json.gpg"

if [ ! -f "$INPUT" ]; then
	echo "Error: $INPUT not found."
	exit 1
fi

cleanup() {
	rm -f "$INPUT"
}
trap cleanup EXIT

echo "Encrypting..."

gpg \
	--compress-algo zlib \
	--compress-level 9 \
	--recipient "$KEYID" \
	--encrypt \
	--output "$OUTPUT.new" \
	"$INPUT"

mv "$OUTPUT.new" "$OUTPUT"

echo "Done."
