# Bash completion for the custom GPG-backed pass script.
# Completes titles first, then usernames belonging to TITLE/.

_pass_find_program() {
    if [[ -n ${PASS_COMPLETION_BIN:-} && -x $PASS_COMPLETION_BIN ]]; then
        printf '%s\n' "$PASS_COMPLETION_BIN"
    else
        type -P pass 2>/dev/null
    fi
}

# Rebuild shell words from COMP_LINE. COMP_WORDS splits at punctuation such
# as @, and may retain backslashes before spaces; parsing the line ourselves
# keeps TITLE/USERNAME intact and turns "Bank\ Of" into "Bank Of".
_pass_parse_line() {
    local line=${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}
    local token= quote= ch escaped=0 active=0 i
    local -a parsed=()

    for ((i=0; i<${#line}; i++)); do
        ch=${line:i:1}
        if (( escaped )); then
            token+=$ch
            escaped=0
            active=1
            continue
        fi
        case $quote in
            "'")
                if [[ $ch == "'" ]]; then quote=; else token+=$ch; fi
                ;;
            '"')
                case $ch in
                    '"') quote= ;;
                    \\) escaped=1 ;;
                    *) token+=$ch ;;
                esac
                ;;
            *)
                case $ch in
                    \\) escaped=1; active=1 ;;
                    "'"|'"') quote=$ch; active=1 ;;
                    [[:space:]])
                        if (( active )); then parsed+=("$token"); fi
                        token=
                        active=0
                        ;;
                    *) token+=$ch; active=1 ;;
                esac
                ;;
        esac
    done
    _PASS_WORDS=("${parsed[@]}" "$token")
}

_pass_ci_starts_with() {
    [[ ${1,,} == "${2,,}"* ]]
}

# Bash treats characters in COMP_WORDBREAKS (notably @) as separate
# completion fragments. Return only the candidate suffix beginning at the
# last such character; Readline will retain the part before it.
_pass_replace_offset() {
    local word=$1 breaks=${COMP_WORDBREAKS-} ch i offset=0
    for ((i=0; i<${#word}; i++)); do
        ch=${word:i:1}
        # Spaces in this parsed token were escaped or quoted in COMP_LINE;
        # they are not Readline word breaks and must stay in the replacement.
        [[ $ch == [[:space:]] ]] && continue
        [[ $breaks == *"$ch"* ]] && offset=$i
    done
    printf '%s\n' "$offset"
}

_pass_complete_entries() {
    local pass_bin entry title prefix mode candidate full offset
    local replace_offset
    local -a candidates=()

    COMPREPLY=()
    _pass_parse_line
    entry=${_PASS_WORDS[${#_PASS_WORDS[@]}-1]-}
    pass_bin=$(_pass_find_program) || return 0
    [[ -n $pass_bin && -x $pass_bin ]] || return 0

    replace_offset=$(_pass_replace_offset "$entry")

    if [[ $entry == */* ]]; then
        mode=users
        title=${entry%%/*}
        prefix=${entry#*/}
        compopt -o filenames +o nospace 2>/dev/null || :
        while IFS= read -r candidate; do
            candidate=${candidate%$'\r'}
            [[ -n $candidate ]] || continue
            _pass_ci_starts_with "$candidate" "$prefix" || continue
            full=$title/$candidate
            COMPREPLY+=("${full:replace_offset}")
        done < <("$pass_bin" __complete users "$title" 2>/dev/null)
    else
        mode=titles
        prefix=$entry
        compopt -o filenames -o nospace 2>/dev/null || :
        while IFS= read -r candidate; do
            candidate=${candidate%$'\r'}
            [[ -n $candidate ]] || continue
            _pass_ci_starts_with "$candidate" "$prefix" || continue
            full=$candidate/
            COMPREPLY+=("${full:replace_offset}")
        done < <("$pass_bin" __complete titles 2>/dev/null)
    fi
}

_pass_completion() {
    local cmd sub entry_index current
    COMPREPLY=()
    _pass_parse_line
    cmd=${_PASS_WORDS[1]-}
    current=${_PASS_WORDS[${#_PASS_WORDS[@]}-1]-}

    if (( ${#_PASS_WORDS[@]} == 2 )); then
        COMPREPLY=( $(compgen -W 'init rekey lock add edit show copy list delete otp qr generate gen' -- "$current") )
        return 0
    fi

    case $cmd in
        edit|show|delete|qr)
            (( ${#_PASS_WORDS[@]} == 3 )) && _pass_complete_entries
            ;;
        copy)
            if (( ${#_PASS_WORDS[@]} == 3 )); then
                if [[ $current == -* ]]; then
                    COMPREPLY=( $(compgen -W '--username --password --notes --url -u -p -n -l' -- "$current") )
                else
                    _pass_complete_entries
                fi
            elif (( ${#_PASS_WORDS[@]} == 4 )); then
                case ${_PASS_WORDS[2]} in
                    -u|-p|-n|-l|--username|--password|--notes|--url) _pass_complete_entries ;;
                esac
            fi
            ;;
        otp)
            if (( ${#_PASS_WORDS[@]} == 3 )); then
                if [[ $current == add* || $current == remove* ]]; then
                    COMPREPLY=( $(compgen -W 'add remove' -- "$current") )
                else
                    _pass_complete_entries
                fi
            elif (( ${#_PASS_WORDS[@]} == 4 )); then
                case ${_PASS_WORDS[2]} in
                    add|remove) _pass_complete_entries ;;
                esac
            fi
            ;;
    esac
    return 0
}

_pass_import_completion() {
    local cur=${COMP_WORDS[COMP_CWORD]-} candidate
    COMPREPLY=()
    (( COMP_CWORD == 1 )) || return 0
    compopt -o filenames 2>/dev/null || :
    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -d -- "$cur")
}

# Needed because our candidates preserve the database's original casing.
# Otherwise Readline rejects e.g. "ch" -> "Chatgpt" before insertion.
if [[ $- == *i* ]]; then
    bind 'set completion-ignore-case on' 2>/dev/null || :
    bind 'set show-all-if-ambiguous on' 2>/dev/null || :
fi

complete -F _pass_completion pass
complete -F _pass_import_completion pass-import
