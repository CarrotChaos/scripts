#!/usr/bin/env bash
# dmenu helper for the custom GPG-backed PASSDB password store.

set -u

PASS_BIN=${PASS_BIN:-"$HOME/scripts/pass"}
PASS_DB=${PASS_DB:-"$HOME/passwords.gpg"}
CACHE_SECONDS=${CACHE_SECONDS:-45}
[[ "$CACHE_SECONDS" =~ ^[0-9]+$ ]] || CACHE_SECONDS=45
PASS_TIMEOUT=${PASS_TIMEOUT:-15}
if [[ "$PASS_TIMEOUT" != off && ! "$PASS_TIMEOUT" =~ ^[0-9]+$ ]]; then PASS_TIMEOUT=15; fi
export PASS_TIMEOUT
START_DIR=$PWD
CACHE_PATH=${CACHE_PATH:-${XDG_CACHE_HOME:-$HOME/.cache}/pass-type-keys-last}

# Resolve paths before changing directory.
[[ "$PASS_BIN" == /* ]] || PASS_BIN=$START_DIR/$PASS_BIN
[[ "$PASS_DB" == /* ]] || PASS_DB=$START_DIR/$PASS_DB
[[ "$CACHE_PATH" == /* ]] || CACHE_PATH=$START_DIR/$CACHE_PATH
PASS_DIR=$(cd -- "$(dirname -- "$PASS_BIN")" && pwd -P) || exit 1
PASS_BIN=$PASS_DIR/$(basename -- "$PASS_BIN")

# pass uses ./totp and ./qr, so run it from its own directory.
cd -- "$PASS_DIR" || {
    printf 'Cannot access pass directory: %s\n' "$PASS_DIR" >&2
    exit 1
}

if [[ -d /dev/shm && -w /dev/shm ]]; then
    TMP=$(mktemp -d /dev/shm/pass-type-keys.XXXXXX) || exit 1
else
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/pass-type-keys.XXXXXX") || exit 1
fi

chmod 700 "$TMP" || exit 1
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[[ -x "$PASS_BIN" ]] || { printf 'pass executable not found: %s\n' "$PASS_BIN" >&2; exit 1; }
[[ -f "$PASS_DB" ]] || { printf 'Password database not found: %s\n' "$PASS_DB" >&2; exit 1; }
command -v dmenu >/dev/null 2>&1 || { printf 'dmenu is required.\n' >&2; exit 1; }

GPG_BIN=$(command -v gpg 2>/dev/null || command -v gpg2 2>/dev/null) || {
    printf 'gpg or gpg2 is required.\n' >&2
    exit 1
}

if [[ -t 0 ]]; then
    GPG_TTY=$(tty 2>/dev/null) && export GPG_TTY
fi

mkdir -p "$(dirname -- "$CACHE_PATH")" || exit 1
chmod 700 "$(dirname -- "$CACHE_PATH")" 2>/dev/null || :

run_dmenu() {
    printf '%s\n' "$1" | dmenu -i -l 15 -p "$2"
}

run_pass() {
    "$PASS_BIN" "$@"
}

get_entries() {
    "$GPG_BIN" --quiet --decrypt --output "$TMP/database" "$PASS_DB" || return 1
    chmod 600 "$TMP/database" || return 1

    local header
    IFS= read -r header < "$TMP/database" || return 1

    case "$header" in
        $'PASSDB\t'*|"PASSDB "*) ;;
        *) printf 'Unsupported database format: expected PASSDB.\n' >&2; return 1 ;;
    esac

    LC_ALL=C awk '
    NR == 1 { next }
    {
        title = username = ""; field = 1; escaped = 0
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (escaped) {
                if (c == "n") value = "\n"
                else if (c == "r") value = "\r"
                else if (c == "t") value = "\t"
                else if (c == "\\" || c == "|") value = c
                else value = "\\" c
                if (field == 1) title = title value
                else if (field == 2) username = username value
                escaped = 0
            } else if (c == "\\") escaped = 1
            else if (c == "|") {
                field++
                if (field == 3) {
                    printf "%s/%s\n", title, username
                    break
                }
            } else if (field == 1) title = title c
            else if (field == 2) username = username c
        }
    }' "$TMP/database" | LC_ALL=C sort -f
}

select_entry() {
    local entries
    entries=$(get_entries) || return 1
    [[ -n "$entries" ]] || return 1
    run_dmenu "$entries" 'Pass: '
}

show_options() {
    local entry=$1 line value first=1 choice
    local has_username=0 has_password=0 has_totp=0 has_url=0
    local -a options=()

    run_pass show "$entry" > "$TMP/show" || return 2

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            'Username:'*)
                value=${line#Username:}; value=${value# }
                [[ -n ${value//[[:space:]]/} ]] && has_username=1
                ;;
            'Password:'*)
                value=${line#Password:}; value=${value# }
                [[ -n "$value" ]] && has_password=1
                ;;
            'Totp:'*|'TOTP:'*)
                value=${line#*:}; value=${value# }
                [[ -n "$value" ]] && has_totp=1
                ;;
            'URL:'*|'Url:'*|'url:'*)
                value=${line#*:}; value=${value# }
                [[ -n "$value" ]] && has_url=1
                ;;
            'Title:'*) ;;
            *)
                if (( first )); then
                    value=$line
                    [[ -n "$value" ]] && has_password=1
                fi
                ;;
        esac
        first=0
    done < "$TMP/show"

    (( has_username )) && options+=("Copy username")
    (( has_password )) && options+=("Copy password")
    (( has_totp )) && options+=("Copy TOTP")
    (( has_url )) && options+=("Copy URL")
    ((${#options[@]})) || return 2

    choice=$(printf '%s\n' "${options[@]}" | dmenu -i -l 15 -p "$entry: ") || return 1

    case "$choice" in
        'Copy username')
            (( has_username )) || return 1
            run_pass copy --username "$entry" >/dev/null || return 2
            ;;
        'Copy password')
            (( has_password )) || return 1
            run_pass copy --password "$entry" >/dev/null || return 2
            ;;
        'Copy TOTP')
            (( has_totp )) || return 1
            [[ -x "$PASS_DIR/totp" ]] || {
                printf 'TOTP helper not executable: %s/totp\n' "$PASS_DIR" >&2
                return 2
            }
            # pass invokes ./totp; cwd is now PASS_DIR.
            run_pass otp "$entry" >/dev/null || return 2
            ;;
        'Copy URL')
            (( has_url )) || return 1
            run_pass copy --url "$entry" >/dev/null || return 2
            ;;
        *) return 1 ;;
    esac

    return 0
}

load_cached_entry() {
    [[ -f "$CACHE_PATH" ]] || return 1
    local timestamp entry now
    IFS= read -r timestamp < "$CACHE_PATH" || return 1
    entry=$(tail -n +2 "$CACHE_PATH") || return 1
    [[ "$timestamp" =~ ^[0-9]+$ && -n "$entry" ]] || return 1
    now=$(date +%s) || return 1
    (( now >= timestamp && now - timestamp <= CACHE_SECONDS )) || return 1
    printf '%s\n' "$entry"
}

save_cached_entry() {
    local tmp_cache
    tmp_cache=$(mktemp "${CACHE_PATH}.XXXXXX") || return 1
    {
        date +%s
        printf '%s\n' "$1"
    } > "$tmp_cache" || { rm -f "$tmp_cache"; return 1; }
    chmod 600 "$tmp_cache" && mv -f "$tmp_cache" "$CACHE_PATH"
}

main() {
    local selected cached result

    if cached=$(load_cached_entry); then
        result=0
        show_options "$cached" || result=$?
        (( result == 0 )) && return 0
        (( result == 2 )) && return 1
    fi

    while selected=$(select_entry); do
        [[ -n "$selected" ]] || continue
        save_cached_entry "$selected" || :
        result=0
        show_options "$selected" || result=$?
        (( result == 0 )) && return 0
        (( result == 2 )) && return 1
    done
}

main "$@"

