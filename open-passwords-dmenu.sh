#!/bin/sh

while :; do
	PASSWORD=$(dmenu -P -p "Unlock passwords:")

	[ -z "$PASSWORD" ] && exit 1

	if printf '%s' "$PASSWORD" | doas /usr/bin/cryptsetup open \
		--key-file=- \
		"$HOME/passwords.img" passwords; then
		break
	fi
done

doas /usr/bin/mount /dev/mapper/passwords "$HOME/passwords"
