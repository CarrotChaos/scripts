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
# Copy password
#
# CLIPBOARD -> Ctrl+V
# PRIMARY   -> middle-click
# ------------------------------------------------------------

copy_password() {
	printf '%s' "$password" |
		xclip -selection clipboard

	printf '%s' "$password" |
		xclip -selection primary

	notify-send "Passwords" "Password copied"
}

# ------------------------------------------------------------
# TOTP
#
# Copy to both X11 selections so that either Ctrl+V or
# middle-click can use the newly generated TOTP.
# ------------------------------------------------------------

copy_totp() {
	if has_totp; then
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

		# Ctrl+V
		printf '%s' "$totp" |
			xclip -selection clipboard

		# Middle-click
		printf '%s' "$totp" |
			xclip -selection primary

		notify-send "Passwords" "TOTP copied"
	fi
}

# ------------------------------------------------------------
# Wait for Ctrl+V or middle click
#
# Ctrl = keycode 37
# V    = keycode 55
# Middle mouse = button 2
#
# xinput only observes the events. It does not consume them.
# ------------------------------------------------------------

wait_for_input_trigger() {
	local detected

	notify-send "Passwords" "Waiting for password paste"

	set +e

	detected=$(
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

	case "$selected" in
		"Copy TOTP after password paste")
			printf '%s' "wait"
			;;

		"Copy TOTP now")
			printf '%s' "copy"
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
login_input)
	# --------------------------------------------------------
	# 1. Ask about TOTP FIRST
	# --------------------------------------------------------

	totp_action="skip"

	if has_totp; then
		totp_action="$(get_totp_option)"
	fi

	# --------------------------------------------------------
	# 2. Type username
	#
	# No Enter is sent.
	# --------------------------------------------------------

	if [ -n "$username" ]; then
		xdotool type -- "$username"
	fi

	# --------------------------------------------------------
	# 3. Copy password to BOTH selections
	# --------------------------------------------------------

	copy_password

	# --------------------------------------------------------
	# 4. Handle TOTP
	# --------------------------------------------------------

	case "$totp_action" in

		wait)
			# Password has already been copied.
			# Wait for the user to paste it.

			if wait_for_input_trigger; then
				copy_totp
			fi
			;;

		copy)
			# Copy TOTP immediately.
			copy_totp
			;;

		skip)
			# Leave password in both selections.
			;;
	esac
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
esac
