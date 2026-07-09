#!/usr/bin/env bash

# Script for pass with dmenu, showing options after selection

set -euo pipefail
shopt -s globstar nullglob

# Directory for password store
prefix="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Find all .gpg files
password_files=("$prefix"/**/*.gpg)
[ "${#password_files[@]}" -eq 0 ] && exit 1

# Normalize to entry names
for i in "${!password_files[@]}"; do
	password_files[$i]="${password_files[$i]#$prefix/}" # remove prefix
	password_files[$i]="${password_files[$i]%.gpg}"     # remove .gpg
done

# Show dmenu for selecting entry
entry=$(printf '%s\n' "${password_files[@]}" | dmenu -l 10 -i -p "Select entry:")

# If no entry selected, exit
[ -z "$entry" ] && exit 0

get_field() {
	local option=$1
	if [ "$option" = "password" ]; then
		printf '%s\n' "$pass_output" | head -n 1
		return
	fi
	printf '%s\n' "$pass_output" | tail -n +2 |
		awk -F': ' -v opt="$option" '$1 == opt {print $2; found=1; exit} END {if (!found) print ""}'
}

has_totp() { printf '%s\n' "$pass_output" | grep -q '^otpauth://'; }

copy_totp() {
	if has_totp; then
		pass otp -c "$entry"
	fi
}

get_url() {
	printf '%s\n' "$pass_output" |
		sed -nE 's/^[[:space:]]*url:[[:space:]]*//p' |
		head -n1
}

get_totp_option() {
	local totp_method
	local selected_label action

	options=$'auto|Autotype TOTP\ncopy|Copy TOTP\nskip|Skip TOTP'

	selected_label=$(pick_from_dmenu "$(printf '%s\n' "$options" | cut -d'|' -f2)" "TOTP action:") || exit 1

	# Map label back to action
	action=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)
	printf '%s\n' "$action"
}

pick_from_dmenu() {
	local input="$1"
	local prompt="$2"
	local selection

	[ -z "$input" ] && return 1
	[ -z "$prompt" ] && return 1
	selection=$(printf '%s\n' "$input" | dmenu -l 10 -p "$prompt") || return 1
	printf '%s\n' "$selection"
}

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

except Exception as e:
    print("daemon_error")
    sys.exit(0)


request = {
    "value": value
}


sock.sendall(
    (json.dumps(request) + "\n").encode()
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


if not data:
    print("no_response")
    sys.exit(0)


line = data.split(b"\n")[0]

reply = json.loads(line.decode())


if "error" in reply:
    print(reply["error"])
else:
    print(reply.get("value",""))
PY
}

require_browser() {
	local result

	result=$(native_query "page has password")

	case "$result" in
	true | false)
		return 0
		;;
	esac

	notify-send "Pass" "Firefox integration unavailable: $result"
	exit 1
}

# Get the line count
if ! pass_output=$(pass show "$entry" 2>/dev/null); then
	exit 1
fi

line_count=$(printf '%s\n' "$pass_output" | wc -l)

if [ "$line_count" -eq 1 ]; then
	options=$(
		cat <<'EOF'
autotype_pwd|Autotype password
copy_pwd|Copy password
EOF
	)
elif [ -z "$(get_field "password")" ]; then
	options=$(
		cat <<'EOF'
autotype_login|Autotype username
copy_login|Copy username
EOF
	)
else
	options=$'autotype_both|Autotype username + password\ncopy_login|Copy username\ncopy_pwd|Copy password\ncopy_totp|Copy TOTP (if exists)\nautotype_login|Autotype username\nautotype_pwd|Autotype password\ntype_url|Type URL (if exists)'

fi

selected_label=$(pick_from_dmenu "$(printf '%s\n' "$options" | cut -d'|' -f2)" "Action for $entry:") || exit 1

# Map label back to action
action=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)

case "$action" in
autotype_both)
	require_browser
	totp_action="skip"
	if has_totp; then
		totp_action="$(get_totp_option)"
	fi

	username=$(get_field "login")
	password=$(get_field "password")

	xdotool type "$username"
	psswd_on_page=$(native_query "page has password")
	if [ "$psswd_on_page" = "true" ]; then
		notify-send "The password input is on the page"
		# just go to the next input and type
		native_query "tab"
		xdotool type "$password"
		xdotool key Return
	else
		notify-send "The password input isn't on the page"
		xdotool key Return
		password_ready=$(native_query "wait password")

		if [ "$password_ready" = "true" ]; then
			notify-send "Found password input!"
			xdotool type "$password"
			xdotool key Return
		else
			notify-send "Password field never appeared"
		fi
	fi

	if [ "$totp_action" = "auto" ]; then
		notify-send "Waiting for TOTP"
		native_query "wait totp"
		notify-send "Found TOTP"
		is_totp=$(native_query "is totp")
		totp="$(pass otp "$entry" | head -n1)"
		if [ "$is_totp" = "true" ]; then
			xdotool type "$totp"
			xdotool key Return
		else
			native_query "tab"
			xdotool type "$totp"
			xdotool key Return
		fi
	elif [ "$totp_action" = "copy" ]; then
		copy_totp
	fi

	;;
copy_login)
	sleep 0.05
	# Copy username
	username=$(get_field "login")
	if [ -n "$username" ]; then
		printf '%s' "$username" | xclip -selection clipboard
	fi
	;;
copy_pwd)
	sleep 0.05
	# Copy password
	pass show -c "$entry"
	;;
copy_totp)
	sleep 0.05
	# Copy TOTP if exists
	copy_totp
	;;
autotype_login)
	sleep 0.2
	username=$(get_field "login")
	xdotool type "$username"
	xdotool key Return
	;;
autotype_pwd)
	sleep 0.05
	password=$(get_field "password")
	xdotool type "$password"
	xdotool key Return
	;;
type_url)
	sleep 0.05
	# Type url
	url=$(get_url)
	if [ -n "$url" ]; then
		xdotool type "$url"
		xdotool key Return
	fi
	;;
esac
