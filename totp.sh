#!/usr/bin/env bash

# Usage:
# ./totp.sh JBSWY3DPEHPK3PXP

SECRET="$1"

if [ -z "$SECRET" ]; then
	echo "Usage: $0 BASE32_SECRET"
	exit 1
fi

# Remove spaces and uppercase
SECRET=$(echo "$SECRET" | tr -d ' ' | tr '[:lower:]' '[:upper:]')

TIME_STEP=30
DIGITS=6

COUNTER=$(($(date +%s) / TIME_STEP))

# Convert counter to 8-byte big-endian
COUNTER_HEX=$(printf "%016x" "$COUNTER")

# Decode Base32 secret
KEY_HEX=$(echo "$SECRET" | base32 -d 2>/dev/null | xxd -p -c256)

# HMAC-SHA1
HMAC=$(printf "$COUNTER_HEX" | xxd -r -p |
	openssl dgst -sha1 -mac HMAC -macopt hexkey:$KEY_HEX -binary |
	xxd -p -c256)

OFFSET=$((0x${HMAC:39:1}))

PART=${HMAC:$((OFFSET * 2)):8}

VALUE=$(((0x$PART & 0x7fffffff) % (10 ** DIGITS)))

printf "%06d\n" "$VALUE"
