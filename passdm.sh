#!/usr/bin/env bash

set -euo pipefail

PASSWORD_STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
MINTOTP="$HOME/scripts/mintotp.py"

# ------------------------------------------------------------
# Find all GNU pass entries
# ------------------------------------------------------------

if [ ! -d "$PASSWORD_STORE" ]; then
	notify-send "Passwords" "Password store not found: $PASSWORD_STORE"
	exit 1
fi

selection=$(
	find "$PASSWORD_STORE" -type f -name '*.gpg' |
		sed "s#^$PASSWORD_STORE/##; s/\.gpg$//" |
		sort |
		dmenu -i -l 10 -p "Select entry:"
)

[ -z "$selection" ] && exit 0

entry_name="$selection"

# ------------------------------------------------------------
# Read entry from GNU pass
# ------------------------------------------------------------

entry_contents=$(pass show "$entry_name") || {
	notify-send "Passwords" "Could not read $entry_name"
	exit 1
}

# Split into lines.
mapfile -t entry_lines <<< "$entry_contents"

if [ "${#entry_lines[@]}" -eq 0 ]; then
	notify-send "Passwords" "Entry is empty."
	exit 1
fi

# ------------------------------------------------------------
# Parse the pass entry
#
# New format:
#
# password
# Username: username
# Totp: ...
# Notes: ...
# URL: ...
#
# Or without a username:
#
# password
# Totp: ...
# Notes: ...
# URL: ...
#
# The password is ALWAYS the first line.
# Username is explicitly identified by "Username:".
#
# Notes may be multiline. Once Notes: is encountered, we stay
# inside the notes section and do not interpret its contents as
# other fields.
# ------------------------------------------------------------

username=""
password="${entry_lines[0]}"
totp_secret=""
url=""
notes=""

metadata_start=1
in_notes=false

for ((i = 1; i < ${#entry_lines[@]}; i++)); do
	line="${entry_lines[i]}"

	# Once Notes: starts, everything following it belongs to notes.
	# This prevents multiline notes from being interpreted as
	# usernames or other metadata.
	if [ "$in_notes" = true ]; then
		if [ -n "$notes" ]; then
			notes+=$'\n'
		fi

		notes+="$line"
		continue
	fi

	case "$line" in
		Username:*|username:*)
			username="${line#*:}"
			username="${username# }"
			;;

		Totp:*|totp:*)
			totp_secret="${line#*:}"
			totp_secret="${totp_secret# }"
			;;

		URL:*|url:*)
			url="${line#*:}"
			url="${url# }"
			;;

		Notes:*|notes:*)
			note="${line#*:}"
			note="${note# }"

			notes="$note"
			in_notes=true
			;;
	esac
done

get_password() {
	printf '%s' "$password"
}

get_username() {
	printf '%s' "$username"
}

get_url() {
	printf '%s' "$url"
}

get_totp_secret() {
	printf '%s' "$totp_secret"
}

has_totp() {
	[ -n "$totp_secret" ]
}

# ------------------------------------------------------------
# TOTP
# ------------------------------------------------------------

copy_totp() {
	if has_totp; then
		totp=$(
			printf '%s\n' "$totp_secret" |
				python3 "$MINTOTP" |
				head -n1
		)

		printf '%s' "$totp" |
			xclip -selection clipboard

		notify-send "Passwords" "TOTP copied"
	fi
}

# ------------------------------------------------------------
# Add TOTP to GNU pass entry
# ------------------------------------------------------------

add_totp() {
	secret=$(
		xclip -o -selection clipboard 2>/dev/null |
			tr -d '\n\r '
	)

	if [ -z "$secret" ]; then
		notify-send "Passwords" "Clipboard is empty."
		return 1
	fi

	# Remove an existing TOTP line, preserving multiline notes.
	new_contents=$(
		printf '%s\n' "$entry_contents" |
			sed '/^[Tt]otp:/d'
	)

	new_contents="${new_contents%$'\n'}"
	new_contents+=$'\n'
	new_contents+="Totp: $secret"
	new_contents+=$'\n'

	printf '%s' "$new_contents" |
		pass insert --multiline --force "$entry_name"

	notify-send "Passwords" "TOTP updated for $entry_name"
}

# ------------------------------------------------------------
# Browser integration
# ------------------------------------------------------------

DAEMON_SOCKET="/tmp/pass-dmenu.sock"

native_query() {
	local value="$1"

	python3 - "$value" "$DAEMON_SOCKET" <<'PY'
import sys
import json
import socket

value = sys.argv[1]
sock_path = sys.argv[2]

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

try:
    sock.connect(sock_path)
except Exception:
    print("daemon_error")
    sys.exit()

sock.sendall(
    (json.dumps({"value": value}) + "\n").encode()
)

data = b""

while True:
    chunk = sock.recv(4096)

    if not chunk:
        break

    data += chunk

    if b"\n" in data:
        break

sock.close()

reply = json.loads(
    data.split(b"\n")[0].decode()
)

if "error" in reply:
    print(reply["error"])
else:
    print(reply.get("value", ""))
PY
}

require_browser() {
	result=$(native_query "page has password")

	case "$result" in
		true | false)
			return
			;;

		*)
			notify-send "Pass" "Firefox integration unavailable: $result"
			exit 1
			;;
	esac
}

# ------------------------------------------------------------
# TOTP action for autotype
# ------------------------------------------------------------

get_totp_option() {
	local selected

	selected=$(
		printf '%s\n' \
			"Autotype TOTP" \
			"Copy TOTP" \
			"Skip TOTP" |
			dmenu -i -l 3 -p "TOTP action:"
	)

	case "$selected" in
		"Autotype TOTP")
			printf '%s' "auto"
			;;

		"Copy TOTP")
			printf '%s' "copy"
			;;

		*)
			printf '%s' "skip"
			;;
	esac
}

# ------------------------------------------------------------
# Build action menu
# ------------------------------------------------------------

options=""

if [ -n "$username" ] && [ -n "$password" ]; then
	options=$'autotype_both|Autotype username + password\ncopy_login|Copy username\ncopy_pwd|Copy password'
elif [ -n "$password" ]; then
	options=$'copy_pwd|Copy password'
elif [ -n "$username" ]; then
	options=$'copy_login|Copy username'
else
	exit 1
fi

if has_totp; then
	options+=$'\ncopy_totp|Copy TOTP'
fi

options+=$'\nadd_totp|Add TOTP'

if [ -n "$url" ]; then
	options+=$'\ncopy_url|Copy URL'
fi

selected_label=$(
	printf '%s\n' "$options" |
		cut -d'|' -f2 |
		dmenu -i -l 10 -p "Action for $entry_name:"
)

[ -z "$selected_label" ] && exit 0

action=$(
	printf '%s\n' "$options" |
		grep -F "|$selected_label" |
		cut -d'|' -f1
)

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

case "$action" in

autotype_both)

	require_browser

	totp_action="skip"

	if has_totp; then
		totp_action="$(get_totp_option)"
	fi

	notify-send "Passwords" "Typing username"

	xdotool type "$username"

	psswd_on_page=$(native_query "page has password")

	if [ "$psswd_on_page" = "true" ]; then

		notify-send "Passwords" "Password field already on page"

		native_query "tab"

		notify-send "Passwords" "Typing password"

		xdotool type "$password"
		xdotool key Return

	else

		notify-send "Passwords" "Waiting for password page"

		xdotool key Return

		password_ready=$(native_query "wait password")

		if [ "$password_ready" = "true" ]; then

			notify-send "Passwords" "Password field found"

			xdotool type "$password"
			xdotool key Return

		else

			notify-send "Passwords" "Password field never appeared"

		fi
	fi

	if [ "$totp_action" = "auto" ]; then

		notify-send "Passwords" "Waiting for TOTP field"

		native_query "wait totp"

		notify-send "Passwords" "Generating TOTP"

		secret=$(get_totp_secret)

		totp=$(
			printf '%s\n' "$secret" |
				python3 "$MINTOTP" |
				head -n1
		)

		is_totp=$(native_query "is totp")

		if [ "$is_totp" = "true" ]; then

			notify-send "Passwords" "Typing TOTP"

			xdotool type "$totp"
			xdotool key Return

		else

			notify-send "Passwords" "Tabbing to TOTP field"

			native_query "tab"

			xdotool type "$totp"
			xdotool key Return

		fi

	elif [ "$totp_action" = "copy" ]; then

		copy_totp

	fi
	;;

copy_login)

	printf '%s' "$username" |
		xclip -selection clipboard
	;;

copy_pwd)

	printf '%s' "$password" |
		xclip -selection clipboard
	;;

add_totp)

	add_totp
	;;

copy_totp)

	copy_totp
	;;

copy_url)

	[ -z "$url" ] && exit 0

	printf '%s' "$url" |
		xclip -selection clipboard
	;;

autotype_login)

	xdotool type "$username"
	xdotool key Return
	;;

esac
