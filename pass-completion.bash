# Bash completion for the custom symmetric-GPG `pass` script.
# Install/source this file from your Bash completion configuration.

_pass_cache_candidates() {
    local prefix=$1 pass_bin uid cache_dir cache_db candidate

    if [[ -n ${PASS_COMPLETION_BIN:-} ]]; then
        pass_bin=$PASS_COMPLETION_BIN
    elif [[ -n ${PASS_BIN:-} ]]; then
        pass_bin=$PASS_BIN
    elif [[ -x $HOME/scripts/pass ]]; then
        pass_bin=$HOME/scripts/pass
    else
        pass_bin=$(type -P pass 2>/dev/null)
    fi
    [[ -n $pass_bin && -x $pass_bin ]] || return 1

    # `open` validates the encrypted database signature and idle lease;
    # it invokes Pinentry only when the cache needs to be rebuilt.
    "$pass_bin" open >/dev/null 2>&1 || return 1

    uid=$(id -u) || return 1
    cache_dir=/dev/shm/pass-cache-$uid
    cache_db=$cache_dir/database
    [[ -r $cache_db ]] || return 1

    while IFS= read -r candidate; do
        [[ $candidate == "$prefix"* ]] && COMPREPLY+=("$candidate")
    done < <(
        LC_ALL=C awk '
            NR == 1 { next }
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
                        if (field == 1) title = title value
                        else if (field == 2) username = username value
                        escaped = 0
                    } else if (c == "\\") escaped = 1
                    else if (c == "|") field++
                    else if (field == 1) title = title c
                    else if (field == 2) username = username c
                    if (field > 2) break
                }
                if (title == "" || title ~ /[\r\n\t]/ || username ~ /[\r\n\t]/)
                    next
                key = tolower(title) SUBSEP tolower(username)
                if (!(key in seen)) {
                    seen[key] = 1
                    print title "/" username
                }
            }
        ' "$cache_db" | LC_ALL=C sort -f
    )
}

_pass_completion() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local command=${COMP_WORDS[1]-}
    local previous=${COMP_WORDS[COMP_CWORD-1]-}
    local cword=$COMP_CWORD
    local -a commands copy_options otp_actions

    COMPREPLY=()
    commands=(init open close rekey add edit show copy delete qr generate otp)
    copy_options=(--username --password --notes --url)
    otp_actions=(add remove)

    if (( cword == 1 )); then
        COMPREPLY=( $(compgen -W "${commands[*]}" -- "$cur") )
        return 0
    fi

    case "$command" in
        show|edit|delete|qr)
            (( cword == 2 )) || return 0
            _pass_cache_candidates "$cur"
            ;;
        copy)
            if (( cword == 2 )) && [[ $cur == -* ]]; then
                COMPREPLY=( $(compgen -W "${copy_options[*]}" -- "$cur") )
            elif (( cword == 2 )) || { (( cword == 3 )) && [[ $previous == -* ]]; }; then
                _pass_cache_candidates "$cur"
            fi
            ;;
        otp)
            if (( cword == 2 )); then
                COMPREPLY=( $(compgen -W "${otp_actions[*]}" -- "$cur") )
                _pass_cache_candidates "$cur"
            elif (( cword == 3 )) && [[ $previous == add || $previous == remove ]]; then
                _pass_cache_candidates "$cur"
            fi
            ;;
    esac
}

complete -o filenames -F _pass_completion pass
