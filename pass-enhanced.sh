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

do_shift_p() {
	xdotool key ctrl+alt+p
}

do_shift_t() {
	xdotool key ctrl+alt+t
}

do_tab_and_check() {
	xdotool key Tab
	sleep 0.05
	xdotool key Shift+p
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
			exit 1
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
			exit 1
		fi
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

		xdotool key shift+t
		wait_for_clip_change "3" "0.05"
	done
}

wait_for_true_pass() {
	printf "" | xclip -selection clipboard
	local timeout="${1:-10}"
	local interval="${2:-0.05}"

	local start=$SECONDS
	local forward count clip
	forward=true
	count=0

	xdotool key Ctrl+alt+p

	while true; do
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		if [ "$clip" = "T" ]; then
			return 0
		fi

		if [ $((SECONDS - start)) -ge "$timeout" ]; then
			notify-send "Timeout waiting for TRUE"
			exit 1
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

		xdotool key Ctrl+alt+p
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
	options=$'auto|Autotype TOTP\nskip|Skip TOTP\ncopy|Copy TOTP\n'

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
	options=$'autotype_both|Autotype Username + Password\nautotype_login|Autotype username\ncopy_login|Copy username\ncopy_pwd|Copy password\nautotype_pwd|Autotype password\ncopy_totp|Copy TOTP (if exists)\ntype_url|Type URL (if exists)'
fi

selected_label=$(pick_from_dmenu "$(printf '%s\n' "$options" | cut -d'|' -f2)" "Action for $entry:") || exit 1

# Map label back to action
action=$(printf '%s\n' "$options" | grep "|$selected_label$" | cut -d'|' -f1)

sleep 0.03
case "$action" in
autotype_both)
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
	xdotool key Ctrl+alt+l # check if the password field is on the page

	clip=$(xclip -o -selection clipboard 2>/dev/null || echo "") # get the clipboard

	if [ "$clip" = "T" ]; then
		# the password is on the page so then check if the next input is the password
		xdotool key Tab
		xdotool key Ctrl+alt+p
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "") # get the clipboard
		if [ "$clip" = "T" ]; then
			xdotool type "$password"
			xdotool key Return
		else
			# or else the password field is a few elements down
			count=1
			while [ "$count" -le 5 ]; do # go 5 more elements down to check if any are password inputs
				xdotool key Tab
				xdotool key Ctrl+alt+p
				clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")

				if [ "$clip" = "T" ]; then # if we find the password field then just type password and press enter
					xdotool type "$password"
					xdotool key Return
					break
				fi
				((count++))
			done
			if [ "$count" -eq 6 ]; then
				# the password field is not on the page, extension possibly failed?
				notify-send "Password field not found on the page. Exiting"
				exit 1
			fi

		fi
	else
		# the password input is not on the page, just press enter
		xdotool key Return

		# wait until the password field is on the page
		xdotool key Ctrl+alt+l
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		SECONDS=0
		while [ "$clip" != "T" ]; do
			if [ "$SECONDS" -gt 10 ]; then
				notify-send "Timed out waiting for password field."
				exit 1
			fi
			xdotool key Ctrl+alt+l
			clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		done

		xdotool key Ctrl+alt+p # check if the current input is the password
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		if [ "$clip" = "T" ]; then
			sleep 0.08
			xdotool type "$password"
			xdotool key Return
		else
			# the password input is down the page
			count=1
			while [ "$count" -le 5 ]; do # go 5 more elements down to check if any are password inputs
				xdotool key Tab
				xdotool key Ctrl+alt+p
				clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")

				if [ "$clip" = "T" ]; then # if we find the password field then just type password and press enter
					xdotool type "$password"
					xdotool key Return
					break
				fi
				((count++))
			done
			if [ "$count" -eq 6 ]; then
				# the password field is not on the page, extension possibly failed?
				notify-send "Password field not found on the page. Exiting"
				exit 1
			fi

		fi

	fi
	sleep 0.4
	if [ "$totp_action" = "auto" ]; then
		xdotool key Ctrl+alt+g
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		SECONDS=0
		while [ "$clip" != "T" ]; do
			if [ "$SECONDS" -ge 10 ]; then
				notify-send "Timed out waiting for TOTP field"
				exit 1
			fi
			xdotool key Ctrl+alt+g
			clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		done

		totp="$(pass otp "$entry" | head -n1)"
		# check if the current field is the totp input
		xdotool key Ctrl+alt+t
		clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")
		if [ "$clip" = "T" ]; then
			xdotool type "$totp"
			xdotool key Return
		else
			# the totp is down the page
			count=1
			while [ "$count" -le 5 ]; do # go 5 more elements down to check if any are totp inputs
				xdotool key Tab
				xdotool key Ctrl+alt+t
				clip=$(xclip -o -selection clipboard 2>/dev/null || echo "")

				if [ "$clip" = "T" ]; then
					xdotool type "$totp"
					xdotool key Return
					break
				fi
				((count++))
			done
			if [ "$count" -eq 6 ]; then
				# the password field is not on the page, extension possibly failed?
				notify-send "TOTP field not found on the page. Exiting"
				exit 1
			fi
		fi
	fi

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
