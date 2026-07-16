#!/bin/sh

while :; do
	PASSWORD=$(dmenu -P -p "Unlock passwords:") || exit 1
	[ -z "$PASSWORD" ] && exit 1

	if printf '%s' "$PASSWORD" | doas /usr/bin/cryptsetup open \
		--key-file=- \
		"$HOME/passwords.img" passwords 2>/dev/null; then
		unset PASSWORD
		break
	fi

	unset PASSWORD
done

if doas /usr/bin/mount /dev/mapper/passwords "$HOME/passwords"; then
	notify-send -i dialog-password "Passwords" "Password vault mounted successfully."
else
	notify-send -i dialog-error "Passwords" "Failed to mount password vault."
	exit 1
fi
