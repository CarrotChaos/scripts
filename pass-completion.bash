# Bash completion for the single-file GPG-backed password store.
# All completion logic lives here; pass requires no Bash-specific code.

_pass_completion_parse_line() {
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
    _PASS_COMPLETION_WORDS=("${parsed[@]}" "$token")
}

_pass_completion_ci_prefix() {
    [[ ${1,,} == "${2,,}"* ]]
}

# Reconstructing COMP_LINE gives us escaped spaces and the full email address.
# Bash may otherwise split words at punctuation such as @.
_pass_completion_replace_offset() {
    local word=$1 breaks=${COMP_WORDBREAKS-} ch i offset=0
    for ((i=0; i<${#word}; i++)); do
        ch=${word:i:1}
        [[ $ch == [[:space:]] ]] && continue
        [[ $breaks == *"$ch"* ]] && offset=$i
    done
    printf '%s\n' "$offset"
}

# Decrypt directly here instead of calling a hidden command in pass.
# Plaintext flows through a pipe and is not written to a temporary file.
_pass_completion_candidates() {
    local mode=$1 wanted_title=${2-}
    local db=${PASS_COMPLETION_DB:-${PASS_DB:-$HOME/passwords.gpg}}
    local gpg_bin

    [[ -r $db ]] || return 0
    gpg_bin=${PASS_GPG_BIN:-}
    if [[ -z $gpg_bin ]]; then
        gpg_bin=$(command -v gpg 2>/dev/null || command -v gpg2 2>/dev/null) || return 0
    fi

    GPG_TTY=$(tty 2>/dev/null) && export GPG_TTY

    "$gpg_bin" --quiet --decrypt "$db" 2>/dev/null | LC_ALL=C awk \
        -v mode="$mode" -v wanted="$wanted_title" '
        function add(c) {
            if (field == 1) title = title c
            else if (field == 2) username = username c
        }
        NR == 1 {
            if (index($0, "PASSDB\t") != 1 && index($0, "PASSDB ") != 1) exit
            next
        }
        {
            title = username = ""
            field = 1
            escaped = 0
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (escaped) {
                    if (c == "n") value = "\n"
                    else if (c == "r") value = "\r"
                    else if (c == "t") value = "\t"
                    else if (c == "\\" || c == "|") value = c
                    else value = "\\" c
                    add(value)
                    escaped = 0
                } else if (c == "\\") escaped = 1
                else if (c == "|") field++
                else add(c)
                if (field > 2) break
            }
            # Newlines/tabs cannot be represented as a single completion.
            if (title == "" || title ~ /[\r\n\t]/ || username ~ /[\r\n\t]/) next
            if (mode == "titles") {
                key = tolower(title)
                if (!(key in seen_title)) {
                    seen_title[key] = 1
                    print title
                }
            } else if (mode == "users" && tolower(title) == tolower(wanted) && username != "") {
                key = tolower(username)
                if (!(key in seen_user)) {
                    seen_user[key] = 1
                    print username
                }
            }
        }'
}

_pass_completion_complete_entry() {
    local entry title prefix candidate full offset
    local replace_offset

    COMPREPLY=()
    _pass_completion_parse_line
    entry=${_PASS_COMPLETION_WORDS[${#_PASS_COMPLETION_WORDS[@]}-1]-}
    replace_offset=$(_pass_completion_replace_offset "$entry")

    if [[ $entry == */* ]]; then
        title=${entry%%/*}
        prefix=${entry#*/}
        compopt -o filenames +o nospace 2>/dev/null || :
        while IFS= read -r candidate; do
            candidate=${candidate%$'\r'}
            [[ -n $candidate ]] || continue
            _pass_completion_ci_prefix "$candidate" "$prefix" || continue
            full=$title/$candidate
            COMPREPLY+=("${full:replace_offset}")
        done < <(_pass_completion_candidates users "$title")
    else
        prefix=$entry
        compopt -o filenames -o nospace 2>/dev/null || :
        while IFS= read -r candidate; do
            candidate=${candidate%$'\r'}
            [[ -n $candidate ]] || continue
            _pass_completion_ci_prefix "$candidate" "$prefix" || continue
            full=$candidate/
            COMPREPLY+=("${full:replace_offset}")
        done < <(_pass_completion_candidates titles)
    fi
}

_pass_completion_main() {
    local command_name current
    COMPREPLY=()
    _pass_completion_parse_line
    command_name=${_PASS_COMPLETION_WORDS[1]-}
    current=${_PASS_COMPLETION_WORDS[${#_PASS_COMPLETION_WORDS[@]}-1]-}

    if (( ${#_PASS_COMPLETION_WORDS[@]} == 2 )); then
        COMPREPLY=( $(compgen -W 'init rekey lock add edit show copy list delete otp qr generate gen' -- "$current") )
        return 0
    fi

    case $command_name in
        edit|show|delete|qr)
            (( ${#_PASS_COMPLETION_WORDS[@]} == 3 )) && _pass_completion_complete_entry
            ;;
        copy)
            if (( ${#_PASS_COMPLETION_WORDS[@]} == 3 )); then
                if [[ $current == -* ]]; then
                    COMPREPLY=( $(compgen -W '--username --password --notes --url -u -p -n -l' -- "$current") )
                else
                    _pass_completion_complete_entry
                fi
            elif (( ${#_PASS_COMPLETION_WORDS[@]} == 4 )); then
                case ${_PASS_COMPLETION_WORDS[2]} in
                    -u|-p|-n|-l|--username|--password|--notes|--url)
                        _pass_completion_complete_entry
                        ;;
                esac
            fi
            ;;
        otp)
            if (( ${#_PASS_COMPLETION_WORDS[@]} == 3 )); then
                if [[ $current == add* || $current == remove* ]]; then
                    COMPREPLY=( $(compgen -W 'add remove' -- "$current") )
                else
                    _pass_completion_complete_entry
                fi
            elif (( ${#_PASS_COMPLETION_WORDS[@]} == 4 )); then
                case ${_PASS_COMPLETION_WORDS[2]} in
                    add|remove) _pass_completion_complete_entry ;;
                esac
            fi
            ;;
    esac
    return 0
}

_pass_import_completion() {
    local current=${COMP_WORDS[COMP_CWORD]-} candidate
    COMPREPLY=()
    (( COMP_CWORD == 1 )) || return 0
    compopt -o filenames 2>/dev/null || :
    while IFS= read -r candidate; do
        COMPREPLY+=("$candidate")
    done < <(compgen -d -- "$current")
}

complete -F _pass_completion_main pass
complete -F _pass_import_completion pass-import
