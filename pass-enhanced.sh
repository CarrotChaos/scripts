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
	local totp_method
	local options yn_options
	local selected_label action

	totp_method=$(get_field "totp_method")
	options=$'auto|Type TOTP (auto-focused field)\nmanual|Type TOTP (tab to field manually)\ncopy|Copy TOTP\nskip|Skip TOTP'

	# If the user has a totp method specified in file, then ask if they want to use that
	yn_options=$(
		cat <<'EOF'
Yes
No
EOF
	)

	if [ -n "$totp_method" ]; then
		selected_label=$(pick_from_dmenu "$yn_options" "Use specified TOTP method? ($totp_method)") || exit 1
		action="${selected_label,,}" # convert to lowercase
		[ "$action" = "yes" ] && {
			printf '%s\n' "$totp_method"
			return
		}
	fi

	selected_label=$(pick_from_dmenu "$(printf '%s\n' "$options" | cut -d'|' -f2)" "TOTP action:") || exit 1

	# Map label back to action
	action=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)
	printf '%s\n' "$action"
}

perform_totp_option() {
	local totp_action="$1"
	local old_clipboard="$2"
	local forward count totp

	xdotool key alt+t

	case "$totp_action" in
	auto | manual)
		SECONDS=0 # special bash variable; OK not to declare local

		if [ "$totp_action" = "auto" ]; then
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" = 'F' ]; do
				if [ "$SECONDS" -ge 10 ]; then
					exit 1
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
						xdotool key --repeat 3 Shift+Tab
					else
						forward=true
						xdotool key --repeat 3 Tab
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

pick_from_dmenu() {
	local input="$1"
	local prompt="$2"
	local selection

	[ -z "$input" ] && return 1
	[ -z "$prompt" ] && return 1
	selection=$(printf '%s\n' "$input" | dmenu -l 10 -p "$prompt") || return 1
	printf '%s\n' "$selection"
}

# Get the line count
pass_output=$(pass show "$entry" 2>/dev/null || {
	exit 1
})
line_count=$(printf '%s\n' "$pass_output" | wc -l)

method=""
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
	options=$'adjacent|Autotype + copy TOTP (adjacent fields)\nwait|Autotype + copy TOTP (wait for password field)\nautotype_login|Autotype username\ncopy_login|Copy username\ncopy_pwd|Copy password\nautotype_pwd|Autotype password\ncopy_totp|Copy TOTP (if exists)\ntype_url|Type URL (if exists)'
	method=$(get_field "autotype_method")
fi

# if the autotype method is specified, then ask the user if they want to use the default method
action=""
if [ -n "$method" ]; then
	yn_options=$(
		cat <<'EOF'
Yes
No
EOF
	)
	selected_label=$(pick_from_dmenu "$yn_options" "Use specified autotype method ($method)?") || exit 1
	action="${selected_label,,}" # convert to lowercase
	if [ "$action" = "yes" ]; then
		action=$method
	fi
fi

if [ -z "$method" ] || [ "$action" = "no" ]; then
	selected_label=$(pick_from_dmenu "$(printf '%s\n' "$options" | cut -d'|' -f2)" "Action for $entry:") || exit 1

	# Map label back to action
	action=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)
fi

sleep 0.03
case "$action" in
adjacent | wait)
	totp_action="skip"
	if has_totp; then
		totp_action=$(get_totp_option)
	fi

	sleep 0.2

	# Save clipboard
	old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "")
	sleep 0.08
	# Autotype using tab to find password field
	username=$(get_field "login")
	password=$(get_field "password")
	if [ -n "$username" ] && [ -n "$password" ]; then
		xdotool type "$username"
		if [ "$action" = "adjacent" ]; then
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
		else # action is wait
			xdotool key Return
			xdotool key alt+p

			SECONDS=0
			while [ "$(xclip -o -selection clipboard 2>/dev/null)" != "T" ]; do
				if [ "$SECONDS" -ge 10 ]; then
					exit 1 # <-- stops everything
				fi
				xdotool key alt+p # Check if password field
				sleep 0.2
			done
		fi
	fi
	xdotool type "$password"
	xdotool key Return
	sleep 0.1
	xdotool key alt+t # alt+t checks if the field is totp

	perform_totp_option "$totp_action" "$old_clipboard" # performs the selected totp option

	;;
autotype_login)
	sleep 0.2
	username=$(get_field "login")
	xdotool type "$username"
	xdotool key Return
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
	password=$(get_field "password")
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
