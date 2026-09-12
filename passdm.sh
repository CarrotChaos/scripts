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

mapfile -t entry_lines <<< "$entry_contents"

if [ "${#entry_lines[@]}" -eq 0 ]; then
	notify-send "Passwords" "Entry is empty."
	exit 1
fi

# ------------------------------------------------------------
# Parse pass entry
#
# First line = password
# Username: username
# Totp: secret
# Notes: ...
# URL: ...
# ------------------------------------------------------------

username=""
password="${entry_lines[0]}"
totp_secret=""
url=""
notes=""

in_notes=false

for ((i = 1; i < ${#entry_lines[@]}; i++)); do
	line="${entry_lines[i]}"

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
# Save current clipboard selections
#
# CLIPBOARD = Ctrl+V
# PRIMARY   = middle-click
# ------------------------------------------------------------

save_clipboard() {
	old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || true)
	old_primary=$(xclip -selection primary -o 2>/dev/null || true)
}

# ------------------------------------------------------------
# Restore previous clipboard selections
# ------------------------------------------------------------

restore_clipboard() {
	printf '%s' "$old_clipboard" | xclip -selection clipboard
	printf '%s' "$old_primary" | xclip -selection primary
}

# ------------------------------------------------------------
# Copy a value to both X11 selections
# ------------------------------------------------------------

copy_to_selections() {
	local value="$1"

	printf '%s' "$value" | xclip -selection clipboard
	printf '%s' "$value" | xclip -selection primary
}

# ------------------------------------------------------------
# Copy a value for 45 seconds, then restore the old clipboard
# ------------------------------------------------------------

copy_temporary() {
	local value="$1"
	local message="$2"

	save_clipboard

	copy_to_selections "$value"

	notify-send "Passwords" "$message"

	sleep 45

	restore_clipboard
}

# ------------------------------------------------------------
# Generate and copy TOTP
#
# This function ONLY copies the TOTP.
# The caller controls the 45-second restoration timer.
# ------------------------------------------------------------

copy_totp() {
	if ! has_totp; then
		return 1
	fi

	local totp

	totp=$(
		printf '%s\n' "$totp_secret" |
			python3 "$MINTOTP" |
			head -n1
	)

	if [ -z "$totp" ]; then
		notify-send "Passwords" "Could not generate TOTP"
		return 1
	fi

	copy_to_selections "$totp"

	notify-send "Passwords" "TOTP copied"
}

# ------------------------------------------------------------
# Wait for Ctrl+V or middle click
#
# Ctrl = keycode 37
# V    = keycode 55
# Middle mouse = button 2
#
# xinput only observes the events. It does not consume them.
#
# Argument:
#   Number of seconds to wait before timing out.
# ------------------------------------------------------------

wait_for_input_trigger() {
	local timeout_seconds="${1:-45}"
	local detected

	notify-send "Passwords" "Waiting for password paste"

	set +e

	detected=$(
		timeout "$timeout_seconds" \
			stdbuf -oL xinput test-xi2 --root 2>/dev/null |
		awk '
		/RawKeyPress/ {
			event = "press"
		}

		/RawKeyRelease/ {
			event = "release"
		}

		/RawButtonPress/ {
			event = "button"
		}

		/^[[:space:]]*detail:/ {
			code = $2

			# Ctrl pressed
			if (event == "press" && code == 37)
				ctrl = 1

			# Ctrl released
			if (event == "release" && code == 37)
				ctrl = 0

			# Ctrl+V
			if (event == "press" && code == 55 && ctrl) {
				print "CTRLV"
				fflush()
				exit
			}

			# Middle mouse button
			if (event == "button" && code == 2) {
				print "MIDDLE"
				fflush()
				exit
			}

			event = ""
		}
		'
	)

	set -e

	case "$detected" in
		CTRLV|MIDDLE)
			return 0
			;;
	esac

	return 1
}

# ------------------------------------------------------------
# TOTP action menu
# ------------------------------------------------------------

get_totp_option() {
	local selected

	selected=$(
		printf '%s\n' \
			"Copy TOTP after password paste" \
			"Skip TOTP" |
			dmenu -i -l 3 -p "TOTP action:"
	)

	if [[ -z "$selected" ]]; then
		return 1
	fi

	case "$selected" in
		"Copy TOTP after password paste")
			printf '%s' "wait"
			;;

		*)
			printf '%s' "skip"
			;;
	esac
}

# ------------------------------------------------------------
# Add TOTP to GNU pass entry
# ------------------------------------------------------------

add_totp() {
	local secret
	local new_contents

	secret=$(
		xclip -o -selection clipboard 2>/dev/null |
			tr -d '\n\r '
	)

	if [ -z "$secret" ]; then
		notify-send "Passwords" "Clipboard is empty."
		return 1
	fi

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
# Build action menu
# ------------------------------------------------------------

options=""

if [ -n "$username" ] && [ -n "$password" ]; then
	options=$'login_input|Type username + copy password\ncopy_login|Copy username\ncopy_pwd|Copy password'
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

# ------------------------------------------------------------
# Type username + copy password
#
# The 45-second timer starts when the password is copied.
#
# If Ctrl+V/middle-click happens during those 45 seconds:
#   - TOTP is generated
#   - TOTP replaces the password
#   - timer continues
#   - original clipboard is restored at 45 seconds
# ------------------------------------------------------------

login_input)
	totp_action="skip"

	if has_totp; then
		totp_action="$(get_totp_option)"
	fi

	# Save original clipboard BEFORE changing anything.
	save_clipboard

	# Type username.
	if [ -n "$username" ]; then
		xdotool type -- "$username"
	fi

	# Copy password to both selections.
	copy_to_selections "$password"

	notify-send "Passwords" "Password copied"

	# Start the 45-second lifetime timer.
	start_time=$SECONDS

	# Wait for Ctrl+V / middle click if requested.
	if [ "$totp_action" = "wait" ]; then

		if wait_for_input_trigger 45; then
			# User triggered TOTP before the timeout.
			copy_totp
		fi
	fi

	# --------------------------------------------------------
	# Make sure the total lifetime is 45 seconds.
	# --------------------------------------------------------

	elapsed=$((SECONDS - start_time))

	if [ "$elapsed" -lt 45 ]; then
		sleep $((45 - elapsed))
	fi

	# Restore the clipboard that existed before this action.
	restore_clipboard
	;;

# ------------------------------------------------------------
# Copy username
# ------------------------------------------------------------

copy_login)
	copy_temporary "$username" "Username copied"
	;;

# ------------------------------------------------------------
# Copy password
# ------------------------------------------------------------

copy_pwd)
	copy_temporary "$password" "Password copied"
	;;

# ------------------------------------------------------------
# Add TOTP
# ------------------------------------------------------------

add_totp)
	add_totp
	;;

# ------------------------------------------------------------
# Copy TOTP
# ------------------------------------------------------------

copy_totp)
	save_clipboard

	if copy_totp; then
		sleep 45
		restore_clipboard
	fi
	;;

# ------------------------------------------------------------
# Copy URL
# ------------------------------------------------------------

copy_url)
	[ -z "$url" ] && exit 0

	copy_temporary "$url" "URL copied"
	;;

esac

