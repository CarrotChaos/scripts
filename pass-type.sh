#!/usr/bin/env bash

set -euo pipefail

QUERY="$HOME/scripts/vault_query.py"

# Select entry
selection=$(
	python "$QUERY" list |
		dmenu -l 10 -i -p "Select entry:"
)

[ -z "$selection" ] && exit 0

entry_name="$selection"

entry_id=$(python "$QUERY" id "$selection")

get_field() {
	python "$QUERY" get "$entry_id" "$1"
}

username=$(get_field username)
password=$(get_field password)
url=$(get_field url)
totp_secret=$(get_field totp)

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

copy_totp() {

	if has_totp; then

		totp=$(printf '%s\n' "$totp_secret" |
			python "$HOME/scripts/mintotp.py" |
			head -n1)

		printf '%s' "$totp" |
			xclip -selection clipboard
	fi
}

pick_from_dmenu() {

	local input="$1"
	local prompt="$2"

	[ -z "$input" ] && return 1

	printf '%s\n' "$input" |
		dmenu -l 10 -p "$prompt"
}

get_totp_option() {

	options=$'auto|Autotype TOTP\ncopy|Copy TOTP\nskip|Skip TOTP'

	selected=$(
		pick_from_dmenu \
			"$(printf '%s\n' "$options" | cut -d'|' -f2)" \
			"TOTP action:"
	)

	printf '%s\n' "$options" |
		grep "|$selected$" |
		cut -d'|' -f1
}

DAEMON_SOCKET="/tmp/pass-dmenu.sock"

native_query() {

	local value="$1"

	python - "$value" "$DAEMON_SOCKET" <<'PY'
import sys
import json
import socket

value=sys.argv[1]
sock_path=sys.argv[2]

sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)

try:
    sock.connect(sock_path)
except:
    print("daemon_error")
    sys.exit()


sock.sendall(
    (json.dumps({"value":value})+"\n").encode()
)


data=b""

while True:

    chunk=sock.recv(4096)

    if not chunk:
        break

    data+=chunk

    if b"\n" in data:
        break


sock.close()


reply=json.loads(
    data.split(b"\n")[0].decode()
)


if "error" in reply:
    print(reply["error"])
else:
    print(reply.get("value",""))
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
		dmenu -l 10 -p "Action for $entry_name:"
)

action=$(
	printf '%s\n' "$options" |
		grep "|$selected_label$" |
		cut -d'|' -f1
)

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

		totp=$(printf '%s\n' "$secret" |
			python "$HOME/scripts/mintotp.py" |
			head -n1)

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
		notify-send "Passwords" "Copying TOTP"

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
	secret=$(xclip -o -selection clipboard 2>/dev/null | tr -d '\n\r ')
	[ -z "$secret" ] && exit 0
	python "$HOME/scripts/totp_edit.py" "$entry_id" "$secret"
	notify-send "Passwords" "TOTP updated for $entry_name"
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
