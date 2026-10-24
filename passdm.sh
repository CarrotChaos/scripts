#!/usr/bin/env bash

set -u

PASS_BIN="$HOME/scripts/pass"
CACHE_SECONDS=45
CACHE_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/pass-type-keys-last"
STORE="${PASS_DIR:-${PASH_DIR:-${PASSWORD_STORE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/pass}}}"
TMP=$(mktemp -d) || exit 1
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$CACHE_PATH")"
chmod 700 "$(dirname "$CACHE_PATH")" 2>/dev/null || :

run_dmenu() {
    printf '%s\n' "$1" | dmenu -i -l 15 -p "$2"
}

get_entries() {
    [[ -d "$STORE" ]] || return 1
    find "$STORE" -type f -name '*.gpg' |
        sed "s|^$STORE/||;s/\.gpg$//" |
        sort -f
}

run_pass() {
    "$PASS_BIN" "$@" && return 0
    command -v st >/dev/null 2>&1 || return 1
    st -e sh -c '
        export GPG_TTY=$(tty)
        "$@"
    ' sh "$PASS_BIN" "$@"
}


get_contents() {
    local entry=$1 gpg_bin=gpg

    command -v gpg2 >/dev/null 2>&1 && gpg_bin=gpg2

    # Try silently using an already-cached GPG passphrase.
    if "$gpg_bin" --batch --pinentry-mode error -dq \
        "$STORE/$entry.gpg" > "$TMP/raw" 2>/dev/null; then
        cat "$TMP/raw"
        return 0
    fi

    # A passphrase is needed: open a real terminal for pinentry.
    if ! command -v st >/dev/null 2>&1; then
        printf '%s\n' "Error: st is not in PATH" >&2
        return 1
    fi

    st -e sh -c '
        export GPG_TTY=$(tty)
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || :

        "$1" show "$2" > "$3"
        rc=$?

        if [ "$rc" -ne 0 ]; then
            printf "\nDecryption failed (exit %s).\nPress Enter to close." "$rc"
            read -r _
        fi
        exit "$rc"
    ' sh "$PASS_BIN" "$entry" "$TMP/raw" || return 1

    cat "$TMP/raw"
}


copy_username() {
    local value=$1 timeout=${PASS_TIMEOUT:-15}

    printf '%s' "$value" | xclip -selection clipboard -i || return 1

    [[ "$timeout" == off ]] && return 0
    (
        sleep "$timeout"
        printf '' | xclip -selection clipboard -i
    ) >/dev/null 2>&1 &
}

select_entry() {
    local entries
    entries=$(get_entries) || return 1
    [[ -n "$entries" ]] || return 1
    run_dmenu "$entries" "Pass: "
}

show_options() {
    local entry=$1 raw line value first=1
    local username="" has_totp=0 password=""
    local options="" choice

    raw=$(get_contents "$entry") || return 2

    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( first )); then
            password=$line
            first=0
            continue
        fi
        case "$line" in
            Username:*)
                value=${line#Username:}
                username=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                ;;
            Totp:*) has_totp=1 ;;
        esac
    done <<< "$raw"

    [[ -n "$username" ]] && options+="Copy username"$'\n'
    [[ -n "$password" ]] && options+="Copy password"$'\n'
    (( has_totp )) && options+="Copy TOTP"$'\n'
    [[ -n "$options" ]] || return 2

    choice=$(run_dmenu "$options" "$entry: ") || return 1

    case "$choice" in
        "Copy username")
            copy_username "$username" && return 0
            ;;
        "Copy password")
            run_pass copy "$entry" && return 0
            ;;
        "Copy TOTP")
            run_pass otp -c "$entry" && return 0
            ;;
        *) return 1 ;;
    esac
    return 2
}

load_cached_entry() {
    [[ -f "$CACHE_PATH" ]] || return 1

    local timestamp entry
    IFS= read -r timestamp < "$CACHE_PATH" || return 1
    entry=$(tail -n +2 "$CACHE_PATH") || return 1

    [[ "$timestamp" =~ ^[0-9]+$ && -n "$entry" ]] || return 1
    (( $(date +%s) - timestamp >= 0 &&
       $(date +%s) - timestamp <= CACHE_SECONDS )) || return 1

    printf '%s\n' "$entry"
}

save_cached_entry() {
    {
        date +%s
        printf '%s\n' "$1"
    } > "$CACHE_PATH"
    chmod 600 "$CACHE_PATH"
}

main() {
    local selected cached result

    if cached=$(load_cached_entry); then
        show_options "$cached"
        result=$?
        (( result == 0 )) && return 0
        (( result == 2 )) && :
    fi

    while selected=$(select_entry); do
        [[ -n "$selected" ]] || continue
        save_cached_entry "$selected"

        show_options "$selected"
        result=$?

        (( result == 0 )) && return 0
        (( result == 2 )) && return 1
    done
}

main "$@"
