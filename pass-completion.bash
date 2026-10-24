_pass_completion() {
    local cur cmd store file entry word
    local -a entries commands
    local has_name

    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}
    commands=(add copy del list otp show tree)

    # Complete subcommands: pass <TAB>
    if (( COMP_CWORD == 1 )); then
        COMPREPLY=( $(compgen -W "${commands[*]}" -- "$cur") )
        return
    fi

    cmd=${COMP_WORDS[1]}

    # Offer OTP clipboard flags before the entry name.
    if [[ "$cmd" == otp && "$cur" == -* ]]; then
        has_name=0
        for (( i=2; i<COMP_CWORD; i++ )); do
            case "${COMP_WORDS[i]}" in
                -c|--clip) ;;
                *) has_name=1 ;;
            esac
        done

        if (( has_name == 0 )); then
            COMPREPLY=( $(compgen -W "-c --clip" -- "$cur") )
            return
        fi
    fi

    # Only these commands take an entry name.
    case "$cmd" in
        copy|del|otp|show) ;;
        *) return ;;
    esac

    # Use the configured password store.
    store=${PASS_DIR:-${XDG_DATA_HOME:-"$HOME/.local/share"}/pass}
    [[ -d "$store" ]] || return

    # Collect entry names, preserving spaces.
    while IFS= read -r -d '' file; do
        entry=${file#"$store"/}
        entry=${entry%.gpg}
        entries+=("$entry")
    done < <(find "$store" -type f -name '*.gpg' -print0 2>/dev/null)

    # Return entries matching the typed prefix.
    for entry in "${entries[@]}"; do
        if [[ "$entry" == "$cur"* ]]; then
            COMPREPLY+=("$entry")
        fi
    done

    # Allow Bash to complete paths containing spaces.
    compopt -o filenames 2>/dev/null || :
}

# Register completion for the command and your alias.
complete -F _pass_completion pass
