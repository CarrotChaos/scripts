# Bash completion for the custom GPG-backed pass application.
# Source this file from ~/.bashrc.

# Keep email addresses together during completion.
if [[ ${COMP_WORDBREAKS-} == *'@'* ]]; then
    COMP_WORDBREAKS=${COMP_WORDBREAKS//@/}
fi

_pass_completion_fetch_ids() {
    local pass_bin=${PASS_COMPLETION_BIN:-"$HOME/scripts/password-manager/pass"}

    [[ -x $pass_bin ]] || return 1

    # Unlock the database using the normal application flow.
    command "$pass_bin" open >/dev/null 2>&1 || return 1

    # List identifiers only (TITLE/USERNAME).
    command "$pass_bin" show 2>/dev/null
}

_pass_completion_add_matches() {
    local prefix=${1-}
    local candidate
    shift || :

    for candidate in "$@"; do
        if [[ ${candidate,,} == "${prefix,,}"* ]]; then
            COMPREPLY+=("$candidate")
        fi
    done
}

_pass_completion_entry_candidates() {
    local prefix=${1-}
    local ids entry title seen_title duplicate
    local -a titles=()

    ids=$(_pass_completion_fetch_ids) || return 0

    if [[ $prefix == */* ]]; then
        # Complete full TITLE/USERNAME identifiers.
        compopt +o nospace 2>/dev/null || :

        while IFS= read -r entry || [[ -n $entry ]]; do
            [[ -n $entry ]] || continue

            if [[ ${entry,,} == "${prefix,,}"* ]]; then
                COMPREPLY+=("$entry")
            fi
        done <<< "$ids"

        return 0
    fi

    # Before the slash, complete distinct titles only.
    while IFS= read -r entry || [[ -n $entry ]]; do
        [[ -n $entry ]] || continue

        title=${entry%%/*}
        duplicate=no

        for seen_title in "${titles[@]}"; do
            if [[ ${seen_title,,} == "${title,,}" ]]; then
                duplicate=yes
                break
            fi
        done

        [[ $duplicate == yes ]] || titles+=("$title")
    done <<< "$ids"

    # Leave the cursor ready for the user to type /.
    compopt -o nospace 2>/dev/null || :

    for title in "${titles[@]}"; do
        if [[ ${title,,} == "${prefix,,}"* ]]; then
            COMPREPLY+=("$title/")
        fi
    done
}

_pass_completion() {
    local cur command_name previous

    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]-}

    # Complete commands.
    if (( COMP_CWORD == 1 )); then
        _pass_completion_add_matches "$cur" \
            init open close lock rekey add edit show copy delete otp qr generate gen
        return 0
    fi

    command_name=${COMP_WORDS[1],,}

    case $command_name in
        show|edit|delete|qr)
            (( COMP_CWORD == 2 )) || return 0
            _pass_completion_entry_candidates "$cur"
            ;;

        copy)
            if (( COMP_CWORD == 2 )); then
                case $cur in
                    -*)
                        _pass_completion_add_matches "$cur" \
                            -u --username -p --password -n --notes -l --url
                        ;;
                    *)
                        _pass_completion_entry_candidates "$cur"
                        ;;
                esac

            elif (( COMP_CWORD == 3 )); then
                previous=${COMP_WORDS[2],,}

                case $previous in
                    -u|--username|-p|--password|-n|--notes|-l|--url)
                        _pass_completion_entry_candidates "$cur"
                        ;;
                esac
            fi
            ;;

        otp)
            if (( COMP_CWORD == 2 )); then
                _pass_completion_add_matches "$cur" add remove
                _pass_completion_entry_candidates "$cur"

            elif (( COMP_CWORD == 3 )); then
                previous=${COMP_WORDS[2],,}

                case $previous in
                    add|remove)
                        _pass_completion_entry_candidates "$cur"
                        ;;
                esac
            fi
            ;;

        generate|gen)
            if (( COMP_CWORD == 2 )) && [[ $cur == -* ]]; then
                _pass_completion_add_matches "$cur" \
                    --length --no-upper --no-lower --no-numbers --no-symbols
            fi
            ;;
    esac

    return 0
}

complete -o filenames -F _pass_completion pass
