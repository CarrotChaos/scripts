#!/usr/bin/env bash

set -u

CACHE_SECONDS=45
CACHE_FILE="pass-type-keys-last"

# ------------------------------------------------------------
# Cache
# ------------------------------------------------------------

if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    CACHE_DIR="$XDG_CACHE_HOME"
else
    CACHE_DIR="$HOME/.cache"
fi

CACHE_PATH="$CACHE_DIR/$CACHE_FILE"

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true


load_cached_entry()
{
    [[ -f "$CACHE_PATH" ]] || return 1

    local timestamp
    local entry
    local now

    timestamp=$(head -n 1 "$CACHE_PATH" 2>/dev/null) || return 1
    entry=$(tail -n +2 "$CACHE_PATH" 2>/dev/null) || return 1

    [[ "$timestamp" =~ ^[0-9]+$ ]] || return 1
    [[ -n "$entry" ]] || return 1

    now=$(date +%s)

    if (( now < timestamp )); then
        return 1
    fi

    if (( now - timestamp > CACHE_SECONDS )); then
        return 1
    fi

    printf '%s\n' "$entry"
}


save_cached_entry()
{
    local entry="$1"

    mkdir -p "$CACHE_DIR"

    {
        printf '%s\n' "$(date +%s)"
        printf '%s\n' "$entry"
    } > "$CACHE_PATH"

    chmod 600 "$CACHE_PATH"
}


# ------------------------------------------------------------
# Tofi
# ------------------------------------------------------------

run_tofi()
{
    local input="$1"
    local prompt="$2"

    tofi \
        --width=900 \
        --height=600 \
        --prompt-text="$prompt" \
        <<< "$input"
}


# ------------------------------------------------------------
# Password store
# ------------------------------------------------------------

get_password_store()
{
    if [[ -n "${PASSWORD_STORE_DIR:-}" ]]; then
        printf '%s\n' "$PASSWORD_STORE_DIR"
    else
        printf '%s\n' "$HOME/.password-store"
    fi
}


get_entries()
{
    local store
    store=$(get_password_store)

    [[ -d "$store" ]] || return 1

    local file
    local entry

    while IFS= read -r -d '' file; do

        # Remove password-store prefix.
        entry="${file#"$store"/}"

        # Remove .gpg suffix.
        entry="${entry%.gpg}"

        printf '%s\n' "$entry"

    done < <(
        find "$store" \
            -type f \
            -name '*.gpg' \
            -print0
    )
}


select_entry()
{
    local entries
    local selected

    entries=$(get_entries) || return 1

    [[ -n "$entries" ]] || return 1

    if selected=$(run_tofi "$entries" "Pass: "); then
        [[ -n "$selected" ]] || return 1

        printf '%s\n' "$selected"

    else
        # Esc from the main selector.
        return 1
    fi
}


# ------------------------------------------------------------
# Get password-store contents
# ------------------------------------------------------------

get_entry_contents()
{
    local entry="$1"

    pass show "$entry"
}


# ------------------------------------------------------------
# Parse entry
#
# First line:
#   password
#
# Optional metadata:
#   Username: ...
#   Totp: ...
# ------------------------------------------------------------

PASSWORD=""
USERNAME=""
TOTP_SECRET=""


parse_entry()
{
    local raw="$1"

    PASSWORD=""
    USERNAME=""
    TOTP_SECRET=""

    local first=1
    local line
    local value

    while IFS= read -r line || [[ -n "$line" ]]; do

        if (( first )); then
            PASSWORD="$line"
            first=0
            continue
        fi

        if [[ "$line" == Username:* ]]; then

            value="${line#Username:}"

            # Trim leading whitespace.
            value="${value#"${value%%[![:space:]]*}"}"

            # Trim trailing whitespace.
            value="${value%"${value##*[![:space:]]}"}"

            USERNAME="$value"

        elif [[ "$line" == Totp:* ]]; then

            value="${line#Totp:}"

            # Trim leading whitespace.
            value="${value#"${value%%[![:space:]]*}"}"

            # Trim trailing whitespace.
            value="${value%"${value##*[![:space:]]}"}"

            TOTP_SECRET="$value"
        fi

    done <<< "$raw"
}


# ------------------------------------------------------------
# Clipboard
# ------------------------------------------------------------

get_clipboard()
{
    wl-paste --no-newline 2>/dev/null
}


set_clipboard()
{
    local value="$1"

    printf '%s' "$value" | wl-copy
}


restore_clipboard_later()
{
    local old_clipboard="$1"
    local copied_value="$2"

    (
        sleep "$CACHE_SECONDS"

        # Only restore if the clipboard still contains the
        # value that this particular copy operation installed.
        #
        # This prevents an old timer from overwriting something
        # copied manually afterward.

        local current

        current=$(wl-paste --no-newline 2>/dev/null) || exit 0

        if [[ "$current" == "$copied_value" ]]; then
            printf '%s' "$old_clipboard" | wl-copy
        fi

    ) >/dev/null 2>&1 &

    disown 2>/dev/null || true
}


copy_to_clipboard()
{
    local value="$1"

    local old_clipboard

    old_clipboard=$(get_clipboard) || old_clipboard=""

    set_clipboard "$value" || return 1

    restore_clipboard_later \
        "$old_clipboard" \
        "$value"
}


# ------------------------------------------------------------
# TOTP
# ------------------------------------------------------------

generate_totp()
{
    local secret="$1"
    local script="$HOME/scripts/mintotp.py"

    [[ -f "$script" ]] || return 1

    python "$script" <<< "$secret"
}


# ------------------------------------------------------------
# Options menu
#
# Returns:
#
#   0 = copied something
#   1 = Esc / cancelled
#   2 = error
# ------------------------------------------------------------

show_options()
{
    local entry="$1"

    local raw

    raw=$(get_entry_contents "$entry") || return 2

    parse_entry "$raw"

    local options=""

    if [[ -n "$USERNAME" ]]; then
        options+="Copy username"$'\n'
    fi

    if [[ -n "$PASSWORD" ]]; then
        options+="Copy password"$'\n'
    fi

    if [[ -n "$TOTP_SECRET" ]]; then
        options+="Copy TOTP"$'\n'
    fi

    if [[ -z "$options" ]]; then
        return 2
    fi

    local choice
    local prompt

    prompt="$entry: "

    if ! choice=$(run_tofi "$options" "$prompt"); then
        # Esc from options.
        return 1
    fi

    case "$choice" in

        "Copy username")
            if copy_to_clipboard "$USERNAME"; then
                return 0
            fi
            ;;

        "Copy password")
            if copy_to_clipboard "$PASSWORD"; then
                return 0
            fi
            ;;

        "Copy TOTP")
            local totp

            totp=$(generate_totp "$TOTP_SECRET") || return 2

            if [[ -n "$totp" ]]; then
                if copy_to_clipboard "$totp"; then
                    return 0
                fi
            fi
            ;;

        *)
            return 1
            ;;
    esac

    return 2
}


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main()
{
    local cached
    local selected
    local result

    # --------------------------------------------------------
    # First check the 45-second cache.
    # --------------------------------------------------------

    if cached=$(load_cached_entry); then

        # Open cached entry's options immediately.
        show_options "$cached"
        result=$?

        case "$result" in

            0)
                # Something was copied.
                exit 0
                ;;

            1)
                # Esc:
                #
                # Cached options
                #       ↓
                #      Esc
                #       ↓
                # Main selector
                #
                ;;
            
            2)
                # Error loading cached entry.
                # Fall through to selector.
                ;;
        esac
    fi


    # --------------------------------------------------------
    # Main selector loop.
    #
    # Esc from options returns here.
    # Esc from selector exits.
    # --------------------------------------------------------

    while true; do

        if ! selected=$(select_entry); then
            # Esc from main selector.
            exit 0
        fi

        # Remember selected entry for 45 seconds.
        save_cached_entry "$selected"


        # ----------------------------------------------------
        # Options loop.
        #
        # Esc returns to the selector.
        # Copy exits the program.
        # ----------------------------------------------------

        show_options "$selected"
        result=$?

        case "$result" in

            0)
                # Something was copied.
                exit 0
                ;;

            1)
                # Esc:
                #
                # Options
                #    ↓
                #   Esc
                #    ↓
                # Selector
                #
                continue
                ;;

            2)
                # Error.
                exit 1
                ;;

        esac

    done
}


main "$@"
