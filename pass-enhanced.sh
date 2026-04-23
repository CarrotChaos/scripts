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

# Helper functions
get_password() { printf '%s\n' "$pass_output" | head -n 1; }

get_field() {
	option=$1
	printf '%s\n' "$pass_output" | tail -n +2 |
		awk -F': ' -v opt="$option" '$1 == opt {print $2; found=1; exit} END {if (!found) print ""}'
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

get_totp_option() {
	totp_method=$(get_field "totp_method")

	options=$'auto|Type TOTP (auto-focused field)\nmanual|Type TOTP (tab to field manually)\ncopy|Copy TOTP\nskip|Skip TOTP'

	# Reorder so preferred is first
	if [ -n "$totp_method" ]; then
		preferred=$(printf '%s\n' "$options" | grep "^$totp_method|")
		rest=$(printf '%s\n' "$options" | grep -v "^$totp_method|")
		options=$(printf '%s\n%s\n' "$preferred" "$rest")
	fi

	# Show only labels
	selected_label=$(printf '%s\n' "$options" | cut -d'|' -f2 | dmenu -l 5 -p "TOTP action:")
	[ -z "$selected_label" ] && return 1

	# Map label back to value
	value=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)

	printf '%s\n' "$value"
}

perform_totp_option() {
	totp_action="$1"
	old_clipboard="$2"
	xdotool key alt+t
	case "$totp_action" in
	auto | manual)
		SECONDS=0
		if [ $totp_action = "auto" ]; then
			# Wait until totp field appears
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" = 'F' ]; do
				if [ "$SECONDS" -ge 10 ]; then
					exit 1 # <-- stops everything
				fi
				xdotool key alt+t
				sleep 0.2
			done
		else
			forward=true
			count=0
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" = 'F' ]; do
				if [ "$SECONDS" -ge 10 ]; then
					exit 1
				fi

				if [ "$forward" = true ]; then
					xdotool key Tab
				else
					xdotool key Shift+Tab
				fi

				sleep 0.05

				count=$((count + 1))

				if [ "$count" -eq 3 ]; then
					count=0
					if [ "$forward" = true ]; then
						forward=false
					else
						forward=true
					fi
				fi
				xdotool key alt+t
			done
		fi
		totp="$(pass otp "$entry" | head -n1)"
		xdotool type "$totp"
		xdotool key Return
		sleep 0.1
		printf "%s" "$old_clipboard" | xclip -selection clipboard
		;;
	copy)
		printf "%s" "$old_clipboard" | xclip -selection clipboard
		copy_totp
		;;
	skip)
		printf "%s" "$old_clipboard" | xclip -selection clipboard
		;;
	esac
}

# Detect the keyboard ID dynamically
keyboard_id=$(xinput list --id-only "AT Translated Set 2 keyboard")

# Get the line count
pass_output=$(pass show "$entry" 2>/dev/null || {
	exit 1
})
line_count=$(printf '%s\n' "$pass_output" | wc -l)

if [ "$line_count" -eq 1 ]; then
	options=$(
		cat <<'EOF'
autotype_pwd|Autotype password
copy_pwd|Copy password
EOF
	)
else
	options=$'sequential|Autotype + copy TOTP (sequential fields)\nwait|Autotype + copy TOTP (wait for password field)\ncopy_login|Copy username\ncopy_pwd|Copy password\ncopy_totp|Copy TOTP (if exists)\ntype_url|Type URL (if exists)'
	method=$(get_field "autotype_method")

	if [ "$method" = "wait" ]; then # If the autotype method is wait then put the wait for password option first
		preferred=$(printf '%s\n' "$options" | grep "^${method}|")
		rest=$(printf '%s\n' "$options" | grep -v "^${method}|")
		options=$(printf '%s\n%s\n' "$preferred" "$rest")
	fi

fi
selected_label=$(printf '%s\n' "$options" | cut -d'|' -f2 | dmenu -l 10 -p "Action for $entry:")
[ -z "$selected_label" ] && return 1

# Map label back to value
value=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)

sleep 0.03
case "$value" in
sequential)
	totp_action=3
	if has_totp; then
		totp_action=$(get_totp_option)
	fi

	sleep 0.2

	# Save clipboard
	old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "")
	printf "%s" "" | xclip -selection clipboard
	sleep 0.08

	# Autotype using tab to find password field
	username=$(get_field "login")
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

		perform_totp_option $totp_action $old_clipboard # performs the selected totp option

	fi
	;;
wait)
	totp_action=3
	if has_totp; then
		totp_action=$(get_totp_option)
	fi

	sleep 0.2
	username=$(get_field "login")
	password=$(get_password)

	# Autotype wait for password field to appear
	if [ -n "$username" ] && [ -n "$password" ]; then
		# Type username + ENTER
		xdotool type "$username"
		xdotool key Return

		old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "") # save the clipboard
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

		perform_totp_option $totp_action $old_clipboard
	fi
	;;
copy_login)
	sleep 0.2
	# Copy username
	username=$(get_field "login")
	if [ -n "$username" ]; then
		copy_to_clipboard "$username"
	fi
	;;
copy_pwd)
	sleep 0.2
	# Copy password
	pass show -c "$entry"
	;;
autotype_pwd)
	sleep 0.2
	password=$(get_password)
	xdotool type "$password"
	xdotool key Return
	;;
copy_totp)
	sleep 0.2
	# Copy TOTP if exists
	copy_totp
	;;
type_url)
	sleep 0.2
	# Type url
	url=$(get_url)
	if [ -n "$url" ]; then
		xdotool type "$url"
		xdotool key Return
	fi
	;;
esac
