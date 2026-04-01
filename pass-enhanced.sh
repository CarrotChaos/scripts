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
dmenu_lines=25

# Then update the two dmenu calls:
entry=$(printf '%s\n' "${password_files[@]}" | dmenu -i -l "$dmenu_lines" -p "Select entry:")

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
EOF
	)
fi

selected=$(printf '%s\n' "$options" | dmenu -i -p "Action for $entry:")

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

# Detect the keyboard ID dynamically
keyboard_id=$(xinput list --id-only "AT Translated Set 2 keyboard")

# Detect keycodes dynamically
ctrl_code=$(xmodmap -pk | awk '/Control_L/{print $1}')
v_code=$(xmodmap -pk | awk '/\<v\>/{print $1}')

wait_for_ctrl_v() {
	local ctrl_pressed=0
	local v_pressed=0

	# Start xinput test in the background with coproc
	coproc XINPUT { xinput test "$keyboard_id"; }

	while read -r line <&"${XINPUT[0]}"; do
		# Detect Ctrl press/release
		if echo "$line" | grep -q "key press.*$ctrl_code"; then
			ctrl_pressed=1
		elif echo "$line" | grep -q "key release.*$ctrl_code"; then
			ctrl_pressed=0
		fi

		# Detect V press/release
		if echo "$line" | grep -q "key press.*$v_code"; then
			v_pressed=1
		elif echo "$line" | grep -q "key release.*$v_code"; then
			v_pressed=0
		fi

		# Both pressed = Ctrl+V detected
		if [ "$ctrl_pressed" -eq 1 ] && [ "$v_pressed" -eq 1 ]; then
			break
		fi
	done

	# Clean up — this kills xinput immediately so no zombie or CPU waste
	kill "${XINPUT_PID}" 2>/dev/null || true
	wait "${XINPUT_PID}" 2>/dev/null || true
}

# Wait a short delay for dmenu to close (e.g., 0.5s)
sleep 0.5

if [ "$line_count" -gt 1 ]; then
	case "$action" in
	1)
		# Autotype: user TAB pass ENTER, then copy TOTP
		username=$(get_login)
		password=$(get_password)
		if [ -n "$username" ] && [ -n "$password" ]; then
			{
				echo "type $username"
				echo "key TAB"
				echo "type $password"
				echo "key ENTER"
			} | dotool
		fi
		copy_totp
		;;
	2)
		# Type username + ENTER
		username=$(get_login)
		if [ -n "$username" ]; then
			{
				echo "type $username"
				echo "key ENTER"
			} | dotool
		fi

		old_clipboard=$(xclip -selection clipboard -o 2>/dev/null || echo "")

		# Copy password
		password=$(get_password)
		echo -n "$password" | xclip -selection clipboard

		wait_for_ctrl_v
		copy_totp

		(
			sleep 45
			echo -n "$old_clipboard" | xclip -selection clipboard
		) &

		;;

	3)
		# Copy username
		username=$(get_login)
		if [ -n "$username" ]; then
			copy_to_clipboard "$username"
		fi
		;;
	4)
		# Copy password
		pass show -c "$entry"
		;;
	5)
		# Copy TOTP if exists
		copy_totp
		;;
	esac
else
	case "$action" in
	1)
		password=$(get_password)
		{
			echo "type $password"
			echo "key ENTER"
		} | dotool
		;;
	2)
		# Copy password
		pass show -c "$entry"
		;;
	esac
fi
