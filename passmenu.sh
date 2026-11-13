#!/usr/bin/env bash
# dmenu frontend for the symmetric-GPG pass store.
# The pass command owns unlocking, cache validation, and cache expiry.
# This script only presents entries and invokes pass actions.

set -u
set -o pipefail

PASS_BIN=${PASS_BIN:-"$HOME/scripts/pass"}
PASS_DB=${PASS_DB:-"$HOME/passwords.gpg"}
PASS_TIMEOUT=${PASS_TIMEOUT:-15}
CACHE_SECONDS=${CACHE_SECONDS:-45}

[[ $PASS_TIMEOUT == off || $PASS_TIMEOUT =~ ^[0-9]+$ ]] || PASS_TIMEOUT=15
[[ $CACHE_SECONDS =~ ^[0-9]+$ ]] || CACHE_SECONDS=45
export PASS_DB PASS_TIMEOUT

START_DIR=$PWD
CACHE_PATH=${CACHE_PATH:-${XDG_CACHE_HOME:-$HOME/.cache}/pass-type-keys-last}

# Resolve relative overrides from the directory where passmenu was invoked.
case $PASS_BIN in
    /*) ;;
    *) PASS_BIN=$START_DIR/$PASS_BIN ;;
esac
case $PASS_DB in
    /*) ;;
    *) PASS_DB=$START_DIR/$PASS_DB ;;
esac
case $CACHE_PATH in
    /*) ;;
    *) CACHE_PATH=$START_DIR/$CACHE_PATH ;;
esac

PASS_DIR=$(cd -- "$(dirname -- "$PASS_BIN")" 2>/dev/null && pwd -P) || {
    printf 'Cannot access pass directory: %s\n' "$(dirname -- "$PASS_BIN")" >&2
    exit 1
}
PASS_BIN=$PASS_DIR/$(basename -- "$PASS_BIN")

[[ -x $PASS_BIN ]] || {
    printf 'pass executable not found or not executable: %s\n' "$PASS_BIN" >&2
    exit 1
}
[[ -f $PASS_DB ]] || {
    printf 'Password database not found: %s\n' "$PASS_DB" >&2
    exit 1
}
command -v dmenu >/dev/null 2>&1 || {
    printf 'dmenu is required.\n' >&2
    exit 1
}

# Secret-bearing temporary output from `pass show` stays in RAM.
[[ -d /dev/shm && -w /dev/shm ]] || {
    printf '/dev/shm is not available or writable.\n' >&2
    exit 1
}
TMP=$(mktemp -d /dev/shm/passmenu.XXXXXX) || {
    printf 'Cannot create temporary directory in /dev/shm.\n' >&2
    exit 1
}
chmod 700 "$TMP" || {
    rm -rf -- "$TMP"
    exit 1
}
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p -- "$(dirname -- "$CACHE_PATH")" || exit 1
chmod 700 "$(dirname -- "$CACHE_PATH")" 2>/dev/null || :

run_pass() {
    "$PASS_BIN" "$@"
}

# `pass show` without arguments is now the public listing interface. It also
# calls decrypt_db(), so it unlocks/populates the shared /dev/shm cache when
# necessary and refreshes the normal idle timer.
get_entries() {
    run_pass show > "$TMP/entries.raw" || return 1
    [[ -s $TMP/entries.raw ]] || {
        printf 'The password store contains no entries.\n' >&2
        return 1
    }
    LC_ALL=C sort -fu "$TMP/entries.raw" > "$TMP/entries" || return 1
    [[ -s $TMP/entries ]]
}

select_entry() {
    get_entries || return 1
    dmenu -i -l 15 -p 'Pass: ' < "$TMP/entries"
}

_has_nonempty_field() {
    local label=$1
    awk -v label="$label" '
        index($0, label ": ") == 1 {
            value = substr($0, length(label) + 3)
            if (value != "") found = 1
        }
        END { exit !found }
    ' "$TMP/show"
}

show_options() {
    local entry=$1 choice result=0
    local -a options=("Copy password")

    # This call validates the entry and refreshes pass's shared cache.
    run_pass show "$entry" > "$TMP/show" || return 2

    # A username, TOTP secret, or URL may legitimately be absent.
    _has_nonempty_field Username && options+=("Copy username")
    _has_nonempty_field Totp && options+=("Copy TOTP")
    _has_nonempty_field URL && options+=("Copy URL")

    choice=$(printf '%s\n' "${options[@]}" | dmenu -i -l 15 -p "$entry: ") || return 1
    [[ -n $choice ]] || return 1

    case $choice in
        'Copy password')
            run_pass copy --password "$entry" >/dev/null || result=$?
            ;;
        'Copy username')
            run_pass copy --username "$entry" >/dev/null || result=$?
            ;;
        'Copy TOTP')
            # `pass otp` generates and copies the current one-time code.
            run_pass otp "$entry" >/dev/null || result=$?
            ;;
        'Copy URL')
            run_pass copy --url "$entry" >/dev/null || result=$?
            ;;
        *)
            return 1
            ;;
    esac

    return "$result"
}

load_cached_entry() {
    [[ -f $CACHE_PATH ]] || return 1

    local timestamp entry now
    IFS= read -r timestamp < "$CACHE_PATH" || return 1
    entry=$(sed -n '2,$p' "$CACHE_PATH") || return 1
    [[ $timestamp =~ ^[0-9]+$ && -n $entry ]] || return 1

    now=$(date +%s) || return 1
    (( now >= timestamp && now - timestamp <= CACHE_SECONDS )) || return 1
    printf '%s\n' "$entry"
}

save_cached_entry() {
    local entry=$1 tmp_cache
    tmp_cache=$(mktemp "${CACHE_PATH}.XXXXXX") || return 1
    {
        date +%s || exit 1
        printf '%s\n' "$entry"
    } > "$tmp_cache" || {
        rm -f -- "$tmp_cache"
        return 1
    }
    chmod 600 "$tmp_cache" && mv -f -- "$tmp_cache" "$CACHE_PATH"
}

main() {
    local selected cached result

    # Re-open the last chosen entry briefly on repeated passmenu invocation.
    if cached=$(load_cached_entry); then
        result=0
        show_options "$cached" || result=$?
        (( result == 0 )) && return 0
        # If the cached entry disappeared, fall through to the fresh list.
        (( result == 2 )) && :
    fi

    while selected=$(select_entry); do
        [[ -n $selected ]] || continue
        save_cached_entry "$selected" || :

        result=0
        show_options "$selected" || result=$?
        (( result == 0 )) && return 0
        (( result == 2 )) && return 1
    done

    return 0
}

main "$@"
