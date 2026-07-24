#!/usr/bin/env bash

SCRIPT_DIR="$HOME/scripts"

choice=$(
	printf '%s\n' \
		"Add Entry" \
		"Edit Password" \
		"Edit TOTP" \
		"Delete Entry" \
		"Encrypt Vault" \
		"Decrypt Vault" |
		dmenu -i -p "Passwords:"
)

case "$choice" in
"Add Entry")
	st -e python3 "$SCRIPT_DIR/add_entry.py"
	;;
"Delete Entry")
	selection=$(
		python3 "$SCRIPT_DIR/vault_query.py" list |
			dmenu -i -l 10 -p "Select entry:"
	) || exit 0

	[ -z "$selection" ] && exit 0

	entry_id=$(
		python3 "$SCRIPT_DIR/vault_query.py" id "$selection"
	)

	confirm=$(
		printf "No\nYes" |
			dmenu -i -p "Delete '$selection'?"
	)

	[ "$confirm" != "Yes" ] && exit 0

	python3 "$SCRIPT_DIR/delete_entry.py" "$entry_id"

	notify-send "Passwords" "Entry deleted."
	;;
"Edit Password" | "Edit TOTP")

	selection=$(
		python3 "$SCRIPT_DIR/vault_query.py" list |
			dmenu -i -l 10 -p "Select entry:"
	) || exit 0

	[ -z "$selection" ] && exit 0

	entry_id=$(
		python3 "$SCRIPT_DIR/vault_query.py" id "$selection"
	)

	if [ "$choice" = "Edit Password" ]; then
		exec st -e python3 "$SCRIPT_DIR/pwedit.py" "$entry_id"
	else
		secret=$(
			xclip -o -selection clipboard 2>/dev/null |
				tr -d '\n\r '
		)

		[ -z "$secret" ] && {
			notify-send "Passwords" "Clipboard is empty."
			exit 1
		}
		python3 "$SCRIPT_DIR/totp_edit.py" "$entry_id" "$secret"
		notify-send "Passwords" "TOTP updated."

	fi
	;;
"Encrypt Vault")
	st -e python3 "$SCRIPT_DIR/encrypt.py"
	;;
"Decrypt Vault")
	st -e python3 "$SCRIPT_DIR/decrypt.py"
	;;
esac
