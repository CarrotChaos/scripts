#!/usr/bin/env bash

# Script for pass with dmenu, showing options after selection

set -euo pipefail
shopt -s globstar nullglob

# Directory for password store
prefix="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Find all .gpg files
password_files=("$prefix"/**/*.gpg)

# Normalize to entry names
for i in "${!password_files[@]}"; do
	password_files[$i]="${password_files[$i]#$prefix/}" # remove prefix
	password_files[$i]="${password_files[$i]%.gpg}"     # remove .gpg
done

# Show dmenu for selecting entry
entry=$(printf '%s\n' "${password_files[@]}" | dmenu -l 10 -i -p "Select entry:")

# If no entry selected, exit
[ -z "$entry" ] && exit 0

# Get the line count
pass_output=$(pass show "$entry" 2>/dev/null || {
	echo "Failed to read entry"
	exit 1
})
line_count=$(printf '%s\n' "$pass_output" | wc -l)

if [ "$line_count" -eq 1 ]; then
	options=$(
		cat <<'EOF'
1: Autotype password
2: Copy password
EOF
	)
else
	options=$(
		cat <<'EOF'
1: Normal Autotype + copy TOTP
2: Modified Autotype + copy TOTP
3: Copy username
4: Copy password
5: Copy TOTP (if exists)
6: Type TOTP (if exists)
7: Type URL (if exists)
EOF
	)
fi

selected=$(printf '%s\n' "$options" | dmenu -l 10 -p "Action for $entry:")

# Extract the number from selected
action=$(echo "$selected" | cut -d: -f1)

# Helper functions
get_password() { printf '%s\n' "$pass_output" | head -n 1; }
get_login() {
	printf '%s\n' "$pass_output" | tail -n +2 |
		grep -Ei '^(login|user|username):' | head -n1 |
		cut -d: -f2- | sed 's/^[ \t]*//'
}
has_totp() { printf '%s\n' "$pass_output" | grep -q '^otpauth://'; }

copy_totp() {
	if has_totp; then
		pass otp -c "$entry"
	fi
}

copy_to_clipboard() {
	local content="$1"
	local duration="${2:-45}"
	echo -n "$content" | xclip -selection clipboard
	(
		sleep "$duration"
		printf "" | xclip -selection clipboard
	) &
}

get_url() {
	printf '%s\n' "$pass_output" |
		sed -nE 's/^[[:space:]]*url:[[:space:]]*//p' |
		head -n1
}

# Detect the keyboard ID dynamically
keyboard_id=$(xinput list --id-only "AT Translated Set 2 keyboard")

# Detect keycodes dynamically
ctrl_code=$(xmodmap -pk | awk '/Control_L/{print $1}')
v_code=$(xmodmap -pk | awk '/\<v\>/{print $1}')

if [ "$line_count" -gt 1 ]; then
	case "$action" in
	1)
		totp_action="3"
		if has_totp; then
			sub_options=$(
				cat <<'EOF'
1: Type TOTP
2: Copy TOTP
3: Skip TOTP
EOF
			)

			sub_selected=$(printf '%s\n' "$sub_options" | dmenu -l 5 -p "TOTP action:")
			sub_action=$(echo "$sub_selected" | cut -d: -f1)

			totp_action="$sub_action"
		fi

		sleep 0.5

		# Save and clear clipboard
		clipboard=$(xclip -selection clipboard -o 2>/dev/null)
		printf "%s" "" | xclip -selection clipboard

		# Autotype: user TAB pass ENTER, then copy TOTP
		username=$(get_login)
		password=$(get_password)
		if [ -n "$username" ] && [ -n "$password" ]; then
			xdotool type "$username"
			xdotool key Tab
			xdotool key alt+p # alt+p checks if the field is password
			count=0

			# Uses the browser extension to check where to tab
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" != "T" ] && [ $count -lt 20 ]; do
				sleep 0.05
				xdotool key Tab
				xdotool key alt+p
				count=$((count + 1)) # run max 20 times
			done

			xdotool type "$password"
			xdotool key Return
			sleep 0.1
			xdotool key alt+t # alt+t checks if the field is totp

			case "$totp_action" in
			1)
				SECONDS=0
				# Wait until totp field appears
				while [ "$(xclip -o -selection clipboard 2>/dev/null)" = 'F' ]; do
					if [ "$SECONDS" -ge 10 ]; then
						exit 1 # <-- stops everything
					fi
					xdotool key alt+t
					sleep 0.2
				done

				totp="$(pass otp "$entry" | head -n1)"
				xdotool type "$totp"
				xdotool key Return

				;;
			2)
				printf "%s" "$clipboard" | xclip -selection clipboard
				copy_totp
				;;
			3)
				printf "%s" "$clipboard" | xclip -selection clipboard
				;;
			esac
		fi
		;;
	2)
		totp_action="3"
		if has_totp; then
			sub_options=$(
				cat <<'EOF'
1: Type TOTP
2: Copy TOTP
3: Skip TOTP
EOF
			)

			sub_selected=$(printf '%s\n' "$sub_options" | dmenu -l 5 -p "TOTP action:")
			sub_action=$(echo "$sub_selected" | cut -d: -f1)

			totp_action="$sub_action"
		fi

		sleep 0.5
		username=$(get_login)
		password=$(get_password)

		# Type username + ENTER
		xdotool type "$username"
		xdotool key Return

		clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "")
		xdotool key alt+p

		SECONDS=0
		while [ "$(xclip -o -selection clipboard 2>/dev/null)" != "T" ]; do
			if [ "$SECONDS" -ge 10 ]; then
				exit 1 # <-- stops everything
			fi
			xdotool key alt+p # Check if password field
			sleep 0.2
		done

		xdotool type "$password"
		xdotool key Return
		sleep 0.1
		xdotool key alt+t
		case "$totp_action" in
		1)
			SECONDS=0
			# Wait until totp field appears
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" = 'F' ]; do
				if [ "$SECONDS" -ge 10 ]; then
					exit 1 # <-- stops everything
				fi
				xdotool key alt+t
				sleep 0.2
			done

			totp="$(pass otp "$entry" | head -n1)"
			xdotool type "$totp"
			xdotool key Return

			;;
		2)
			printf "%s" "$clipboard" | xclip -selection clipboard
			copy_totp
			;;
		3)
			printf "%s" "$clipboard" | xclip -selection clipboard
			;;
		esac
		;;
	3)
		sleep 0.5
		# Copy username
		username=$(get_login)
		if [ -n "$username" ]; then
			copy_to_clipboard "$username"
		fi
		;;
	4)
		sleep 0.5
		# Copy password
		pass show -c "$entry"
		;;
	5)
		sleep 0.5
		# Copy TOTP if exists
		copy_totp
		;;
	6)
		sleep 0.5
		# Type totp
		totp="$(pass otp "$entry" | head -n1)"
		xdotool type "$totp"
		xdotool key Return
		;;
	7)
		sleep 0.5
		# Type url
		url=$(get_url)
		if [ -n "$url" ]; then
			xdotool type "$url"
			xdotool key Return
		fi
		;;
	esac
else
	case "$action" in
	1)
		password=$(get_password)
		xdotool type "$password"
		xdotool key Return
		;;
	2)
		# Copy password
		pass show -c "$entry"
		;;
	esac
fi
