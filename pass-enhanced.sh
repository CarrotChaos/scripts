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

do_alt_p() {
	xdotool key alt+p
}

do_alt_t() {
	xdotool key alt+t
}

do_tab_and_check() {
	xdotool key Tab
	sleep 0.05
	xdotool key alt+p
}

wait_for_clip() {
	local timeout="${1:-10}"
	local interval="${2:-0.05}"
	local predicate="$3" # function name
	local action="$4"    # optional

	local start=$SECONDS
	local clip

	while true; do
		if [ -n "$action" ]; then
			"$action"
		fi

		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")

		if "$predicate" "$clip"; then
			return 0
		fi

		if ((SECONDS - start >= timeout)); then
			notify-send "Timeout waiting for clipboard condition"
			return 1
		fi

		sleep "$interval"
	done
}

wait_for_clip_change() {
	local timeout="${1:-10}"
	local interval="${2:-0.05}"
	local action="${3:-""}"

	local start=$SECONDS
	local clip

	while true; do
		[ -n "$action" ] && "$action"

		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		sleep "$interval"

		# accept ANY valid state
		if [ "$clip" = "T" ] || [ "$clip" = "F" ]; then
			return 0
		fi

		if [ $((SECONDS - start)) -ge "$timeout" ]; then
			notify-send "Timeout waiting for clipboard ready state"
			return 1
		fi
	done
}

wait_for_true() {
	printf "" | xclip -selection clipboard
	local timeout="${1:-10}"
	local interval="${2:-0.05}"
	local action="${3:-""}"

	local start=$SECONDS
	local clip

	while true; do
		if [ -n "$action" ]; then
			"$action"
			wait_for_clip_change "3" "0.05"
		fi

		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")

		if [ "$clip" = "T" ]; then
			return 0
		fi

		if [ $((SECONDS - start)) -ge "$timeout" ]; then
			notify-send "Timeout waiting for TRUE"
			return 1
		fi
		sleep "$interval"
	done
}

wait_for_true_totp() {
	printf "" | xclip -selection clipboard
	local timeout="${1:-10}"
	local interval="${2:-0.05}"

	local start=$SECONDS
	local forward count clip
	forward=true
	count=0

	while true; do
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		if [ "$clip" = "T" ]; then
			return 0
		fi

		if [ $((SECONDS - start)) -ge "$timeout" ]; then
			notify-send "Timeout waiting for TRUE"
			return 1
		fi

		if [ "$forward" = true ]; then
			xdotool key Tab
		else
			xdotool key Shift+Tab
		fi

		sleep $interval
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
		wait_for_clip_change "3" "0.05"
	done
}

restore_clipboard() {
	printf "%s" "$1" | xclip -selection clipboard
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

	printf "" | xclip -selection clipboard
	xdotool key alt+t
	wait_for_clip_change "3" "0.05" "" # wait up to 3 seconds for clipboard to change

	case "$totp_action" in
	auto | manual)

		if [ "$totp_action" = "auto" ]; then
			wait_for_true "10" "0.1" "do_alt_t"
		else
			wait_for_true_totp "10" "0.1"
		fi

		totp="$(pass otp "$entry" | head -n1)"
		xdotool type "$totp"
		xdotool key Return
		sleep 0.1
		restore_clipboard "$old_clipboard"
		;;
	copy)
		restore_clipboard "$old_clipboard"
		copy_totp
		;;
	skip)
		restore_clipboard "$old_clipboard"
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
		totp_action="$(get_totp_option)"
	fi
	# Save clipboard
	old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "")
	printf "" | xclip -selection clipboard

	sleep 0.2
	username=$(get_field "login")
	password=$(get_field "password")

	xdotool type "$username"
	if [ "$action" = "adjacent" ]; then
		# Autotype using tab to find password field
		wait_for_true "5" "0.05" "do_tab_and_check" # wait up to 5s for alt+p + tab to be T
	else                                         # action is wait
		xdotool key Return
		wait_for_true "10" "0.05" "do_alt_p" # wait up to 10s for alt+p to be T

	fi
	xdotool type "$password"
	xdotool key Return
	sleep 0.02

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
		printf '%s' "$username" | xclip -selection clipboard
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
