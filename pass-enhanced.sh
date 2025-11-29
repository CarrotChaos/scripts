#!/usr/bin/env bash

# Script for pass with dmenu, showing options after selection

set -euo pipefail
shopt -s globstar nullglob

# Directory for password store
prefix="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Find all .gpg files
password_files=("$prefix"/*.gpg "$prefix"/**/*.gpg)

# Normalize to entry names
for i in "${!password_files[@]}"; do
    password_files[$i]="${password_files[$i]#$prefix/}"   # remove prefix
    password_files[$i]="${password_files[$i]%.gpg}"       # remove .gpg
done

# Show dmenu for selecting entry
entry=$(printf '%s\n' "${password_files[@]}" | dmenu -i -p "Select entry:")

# If no entry selected, exit
[ -z "$entry" ] && exit 0

# Get the line count
line_count=$(( $(pass show "$entry" | wc -l) ))

if [ "$line_count" -eq 1 ]; then
    options=$(cat <<'EOF'
1: Autotype password
2: Copy password
EOF
)
else
    options=$(cat <<'EOF'
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
get_password() {
    pass show "$entry" | head -n 1
}

get_login() {
    pass show "$entry" | tail -n +2 | grep -i '^login:' | head -n1 | cut -d: -f2- | sed 's/^[ \t]*//'
}

has_totp() {
    pass show "$entry" | grep -q '^otpauth://'
}

copy_totp() {
    if has_totp; then
        pass otp -c "$entry"
    fi
}

copy_to_clipboard() {
    local content="$1"
    local duration="${2:-45}"  # Default to 45s like pass clip
    echo -n "$content" | xclip -selection clipboard
    printf "" | xclip -selection clipboard
}

# Detect the keyboard ID dynamically
keyboard_id=$(
    xinput list |
    awk '
        /keyboard/i && /id=[0-9]/ {
            for (i=1; i<=NF; i++)
                if ($i ~ /id=[0-9]+/) {
                    gsub("id=", "", $i)
                    print $i
                    exit
                }
        }'
)


# Fail safely if not found
if [ -z "$keyboard_id" ]; then
    exit 1
fi

# Detect keycodes dynamically
ctrl_code=$(xmodmap -pk | awk '/Control_L/{print $1}')
v_code=$(xmodmap -pk | awk '/\<v\>/{print $1}')

wait_for_ctrl_v() {
    local ctrl_pressed=0
    local v_pressed=0

    while read -r line; do
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

        # Both pressed simultaneously = Ctrl+V
        if [ "$ctrl_pressed" -eq 1 ] && [ "$v_pressed" -eq 1 ]; then
            break
        fi
    done < <(xinput test "$keyboard_id")
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
                xdotool type --delay 10 "$username"
                xdotool key Tab
                xdotool type --delay 10 "$password"
                xdotool key Return
            fi
            copy_totp
            ;;
        2)
        # Type username + ENTER
            username=$(get_login)
            if [ -n "$username" ]; then
            xdotool type --delay 10 "$username"
                xdotool key Return
            fi

        # Copy password
        password=$(get_password)
        echo -n "$password" | xclip -selection clipboard

        wait_for_ctrl_v

        copy_totp
        
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
            xdotool type --delay 10 "$password"
            xdotool key Return
	    ;;
	2)
            # Copy password
            pass show -c "$entry"
            ;;
    esac
fi
