_pass_completion() {
    local cur cmd store file entry i has_name
    local -a entries commands
    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}
    commands=(add a copy c del d list l otp o show s tree t)

    if (( COMP_CWORD == 1 )); then
        COMPREPLY=( $(compgen -W "${commands[*]}" -- "$cur") )
        return
    fi

    cmd=${COMP_WORDS[1]}
    case "$cmd" in
        a*) cmd=add ;;
        c*) cmd=copy ;;
        d*) cmd=del ;;
        l*) cmd=list ;;
        o*) cmd=otp ;;
        s*) cmd=show ;;
        t*) cmd=tree ;;
    esac

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

    case "$cmd" in
        copy|del|otp|show) ;;
        *) return ;;
    esac

    store=${PASS_DIR:-${PASH_DIR:-${PASSWORD_STORE_DIR:-${XDG_DATA_HOME:-"$HOME/.local/share"}/pass}}}
    [[ -d "$store" ]] || return

    while IFS= read -r -d '' file; do
        entry=${file#"$store"/}
        entry=${entry%.gpg}
        [[ "$entry" == "$cur"* ]] && entries+=("$entry")
    done < <(find "$store" -type f -name '*.gpg' -print0 2>/dev/null)

    COMPREPLY=("${entries[@]}")
    compopt -o filenames 2>/dev/null || :
}

complete -F _pass_completion pass

