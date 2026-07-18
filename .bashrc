#!/usr/bin/env bash

###############################################################################
# Environment (interactive and non-interactive)
###############################################################################

# shellcheck source=/dev/null
[[ -f ~/.env.sh ]] && . ~/.env.sh

path_prepend() {
    [[ -d "$1" && ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH"
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/Code/dotfiles/scripts"

grep -qi microsoft /proc/version 2>/dev/null && _IS_WSL=1

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

[[ $- != *i* ]] && return

###############################################################################
# Common Aliases
###############################################################################

alias g='git'
alias gau='git add -u'
alias gaa='git add -A'
alias gap='git add -p'
alias gc='git commit'
alias gcm='git commit -m'
alias gwip='git add -A && git commit -m wip'
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline -20'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias grep='grep --color=auto'
alias sudo='sudo '
alias showpath='printf "%s\n" "$PATH" | tr ":" "\n"'
alias a='claude -p'

if [[ -n "$_IS_WSL" ]]; then
    alias pbcopy='sed "s/\x1B\[[0-9;]*[mK]//g" | clip.exe'
    alias pbpaste='powershell.exe -noprofile -command "Get-Clipboard"'
elif command -v wl-copy >/dev/null 2>&1; then
    alias pbcopy='wl-copy'
    alias pbpaste='wl-paste'
fi

venv() {
    if [[ -d ".venv" ]]; then
        source .venv/bin/activate
    else
        python -m venv .venv && source .venv/bin/activate &&
            pip install --upgrade pip
    fi
}

if command -v eza >/dev/null 2>&1; then
    alias lg='eza --git -l --color=auto'
    alias ll='eza -lh --color=auto'
    alias ls='eza --color=auto'
    alias tree='eza --tree --color=auto'
fi

mkcd() {
    mkdir -p "$1" && cd "$1" || return
}

gr() { cd "$(git rev-parse --show-toplevel)" || return; }

portkill() {
    : "${1:?port required}"
    lsof -ti ":$1" | xargs -r kill
}

# Resolve a project (optionally a worktree) to its directory, printed to stdout.
_p_resolve() {
    local code_dir="$HOME/Code"
    local pdir="$code_dir/${1:?project name required}"
    local wt_list wt_count target

    [[ -d "$pdir" ]] ||
        {
            printf 'Not found: %s\n' "$1" >&2
            return 1
        }

    wt_list="$(git -C "$pdir" worktree list 2>/dev/null)" ||
        {
            printf '%s\n' "$pdir"
            return
        }

    wt_count="$(wc -l <<<"$wt_list")"
    ((wt_count > 1)) ||
        {
            printf '%s\n' "$pdir"
            return
        }

    if [[ -n "${2-}" ]]; then
        target="$(awk -v wt="$2" '
            { br = $NF; gsub(/^\[|\]$/, "", br) }
            br == wt { print $1; exit }
        ' <<<"$wt_list")"
    else
        target="$(awk '
            { fallback=$1 }
            /\[main\]/   { preferred=$1 }
            /\[master\]/ && !preferred { preferred=$1 }
            !/\(bare\)/ && !first { first=$1 }
            END { print preferred ? preferred : first ? first : fallback }
        ' <<<"$wt_list")"
    fi

    [[ -n "$target" ]] ||
        {
            echo "Worktree not found: ${2:-default}" >&2
            return 1
        }
    printf '%s\n' "$target"
}

p() {
    local target
    target="$(_p_resolve "$@")" || return
    cd "$target" || return
}

pc() {
    local target
    target="$(_p_resolve "$@")" || return
    code "$target"
}

_p_completions() {
    local code_dir="$HOME/Code"
    local cur="${COMP_WORDS[$COMP_CWORD]}"
    if [[ $COMP_CWORD -eq 1 ]]; then
        local words
        words="$(command ls -1 "$code_dir" 2>/dev/null)"
        mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
    elif [[ $COMP_CWORD -eq 2 ]]; then
        local pdir="$code_dir/${COMP_WORDS[1]}"
        if [[ -d "$pdir" ]]; then
            branches="$(
                git -C "$pdir" worktree list 2>/dev/null |
                    awk '{gsub(/[\[\]]/, "", $3); if ($3) print $3}'
            )"
            mapfile -t COMPREPLY \
                < <(compgen -W "$branches" -- "$cur")
        fi
    fi
}
complete -F _p_completions p pc

###############################################################################
# Bash Completions
###############################################################################

for _bashcomp in \
    /usr/share/bash-completion/bash_completion \
    /etc/bash_completion; do
    if [[ -r "$_bashcomp" ]]; then
        # shellcheck source=/dev/null
        . "$_bashcomp"
        break
    fi
done
unset _bashcomp

###############################################################################
# History
###############################################################################

shopt -s histappend

if [[ ! "${HISTTIMEFORMAT@a}" == *r* ]]; then
    export HISTTIMEFORMAT="%F %T "
fi

export HISTCONTROL=ignoreboth
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear:pwd:jobs:cd"
export HISTSIZE=4000
export HISTFILESIZE=10000

###############################################################################
# Kubernetes & Docker/Podman
###############################################################################

export DOCKER_CLI_HINTS="false"

alias k='kubectl'

if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
fi

if command -v podman >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=podman
    if [ -S "${XDG_RUNTIME_DIR:-}/podman/podman.sock" ]; then
        export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    fi
    alias d='podman'
elif command -v docker >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=docker
    alias d='docker'
fi

kube_info() {
    export DISPLAY_KUBE_INFO=1
}

disable_kube_info() {
    unset DISPLAY_KUBE_INFO
}

###############################################################################
# Cloud
###############################################################################

# shellcheck source=/dev/null
[[ -f "$HOME/.config/op/plugins.sh" ]] && . "$HOME/.config/op/plugins.sh"

if command -v aws_completer >/dev/null 2>&1; then
    complete -C aws_completer aws
fi

# shellcheck source=/dev/null
[[ -r "$HOME/lib/azure-cli/az.completion" ]] &&
    . "$HOME/lib/azure-cli/az.completion"

###############################################################################
# Prompt
###############################################################################

shopt -s promptvars
declare -a _prompt_text=()

function clr {
    local -n _out="$1"
    [[ -n "$2" ]] || return
    local i=${#_prompt_text[@]}
    _prompt_text[i]="$2"
    _out+="\[\033[0;$3\]\${_prompt_text[$i]}\[\033[0m\]"
}

function _git_dir_is_bare {
    local line section="" value bare=false
    [[ -r "$1/config" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line%%;*}"
        line="${line//[[:space:]]/}"
        line="${line,,}"
        if [[ "$line" == \[*\] ]]; then
            section="$line"
        elif [[ "$section" == "[core]" && "$line" == "bare" ]]; then
            bare=true
        elif [[ "$section" == "[core]" && "$line" == bare=* ]]; then
            value="${line#bare=}"
            value="${value#\"}"
            value="${value%\"}"
            if [[ "$value" == true || "$value" == yes || "$value" == on ||
                "$value" =~ ^[+-]?[0-9]+$ && ! "$value" =~ ^[+-]?0+$ ]]; then
                bare=true
            else
                bare=false
            fi
        fi
    done <"$1/config"

    [[ "$bare" == true ]]
}

function git_prompt {
    local d="$PWD" gd="" git_file=false

    while [[ -n "$d" ]]; do
        if [[ -d "$d/.git" ]]; then
            gd="$d/.git"
            break
        fi
        if [[ -f "$d/.git" ]]; then
            git_file=true
            read -r gd <"$d/.git"
            if [[ "$gd" == "gitdir: "* ]]; then
                gd="${gd#gitdir: }"
                [[ "$gd" != /* ]] && gd="$d/$gd"
            fi
            break
        fi
        [[ "$d" == "/" ]] && break
        d="${d%/*}"
        [[ -n "$d" ]] || d="/"
    done
    [[ -z "$gd" || ! -f "$gd/HEAD" ]] && return
    if [[ "$git_file" == true && ! -f "$gd/commondir" ]] &&
        _git_dir_is_bare "$gd"; then
        _git_prompt_out="[hub] "
        return
    fi

    local head line oid="" branch="" state="" rebase_dir=""
    read -r head <"$gd/HEAD"

    if [[ -d "$gd/rebase-merge" ]]; then
        state="|REBASE"
        rebase_dir="$gd/rebase-merge"
    elif [[ -d "$gd/rebase-apply" ]]; then
        rebase_dir="$gd/rebase-apply"
        if [[ -f "$rebase_dir/applying" ]]; then
            state="|AM"
        else
            state="|REBASE"
        fi
    elif [[ -f "$gd/MERGE_HEAD" ]]; then
        state="|MERGE"
    elif [[ -f "$gd/CHERRY_PICK_HEAD" ]]; then
        state="|CHERRY"
    elif [[ -f "$gd/REVERT_HEAD" ]]; then
        state="|REVERT"
    elif [[ -f "$gd/BISECT_LOG" ]]; then
        state="|BISECT"
    fi

    if [[ "$head" != "ref: "* ]]; then
        oid="$head"
        if [[ -n "$rebase_dir" && -f "$rebase_dir/head-name" ]]; then
            read -r branch <"$rebase_dir/head-name"
            branch="${branch#refs/heads/}"
        fi
        [[ -z "$branch" || "$branch" == "detached HEAD" ]] && branch="DETACHED"
    else
        local common_gd="$gd" ref="${head#ref: }"
        [[ "$ref" == refs/* ]] || return
        if [[ -f "$gd/commondir" ]]; then
            read -r common_gd <"$gd/commondir"
            [[ "$common_gd" != /* ]] && common_gd="$gd/$common_gd"
        fi

        if [[ "$ref" == refs/heads/* ]]; then
            branch="${ref#refs/heads/}"
        else
            branch="${ref#refs/}"
        fi
        local lookup_ref="$ref" ref_value="" ref_path="" depth=0
        while ((depth < 8)); do
            ref_path="$common_gd/$lookup_ref"
            [[ -f "$gd/$lookup_ref" ]] && ref_path="$gd/$lookup_ref"
            [[ -f "$ref_path" ]] || break
            ref_value=""
            read -r ref_value <"$ref_path" || lookup_ref=""
            if [[ "$ref_value" == "ref: refs/"* ]]; then
                lookup_ref="${ref_value#ref: }"
                ((depth += 1))
            else
                if [[ "$ref_value" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]]; then
                    oid="$ref_value"
                fi
                lookup_ref=""
                break
            fi
        done
        ((depth < 8)) || lookup_ref=""

        if [[ -z "$oid" && -n "$lookup_ref" && -f "$common_gd/packed-refs" ]]; then
            while read -r line; do
                if [[ "$line" == *" $lookup_ref" ]]; then
                    oid="${line%% *}"
                    break
                fi
            done <"$common_gd/packed-refs"
        fi
    fi

    if ((${#branch} > 30)); then
        branch="${branch:0:14}…${branch: -15}"
    fi
    if [[ -n "$oid" ]]; then
        _git_prompt_out="[$branch@${oid:0:7}$state] "
    else
        _git_prompt_out="[$branch$state] "
    fi
}

function kube_prompt {
    [[ -z "$DISPLAY_KUBE_INFO" ]] && return
    command -v kubectl >/dev/null 2>&1 || return
    local ctx ns
    ctx=$(kubectl config current-context 2>/dev/null)
    [[ -n "$ctx" ]] || return
    ns=$(kubectl config view --minify \
        --output 'jsonpath={..namespace}' 2>/dev/null)
    [[ -z "$ns" ]] && ns="default"
    _kube_prompt_out="[$ctx:$ns] "
}

function set_prompt {
    local exit_status=${__prompt_exit:-0}

    local ssh uchar uchar_color
    _prompt_text=()
    _git_prompt_out=""
    git_prompt
    _kube_prompt_out=""
    kube_prompt
    [[ -n "$SSH_CONNECTION" ]] && ssh="[${USER}@${HOSTNAME%%.*}] "
    [[ $EUID -eq 0 ]] && uchar="#" || uchar="$"
    [[ $exit_status -ne 0 ]] && uchar_color="91m" || uchar_color="93m"

    local pwd_str="${PWD/#$HOME/\~}"
    PS1=""
    clr PS1 "$ssh" "91m"
    clr PS1 "$_git_prompt_out" "94m"
    clr PS1 "$_kube_prompt_out" "96m"
    clr PS1 "$pwd_str" "92m"
    PS1+=" "
    clr PS1 "$uchar" "$uchar_color"
    PS1+=" "

    return "$exit_status"
}

PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND%;}; }"
PROMPT_COMMAND+='__prompt_exit=$?; set_prompt'

###############################################################################
# .NET
###############################################################################

_dotnet_bash_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local -a candidates
    mapfile -t candidates < \
        <(dotnet complete --position "${COMP_POINT}" "${COMP_LINE}" 2>/dev/null)
    mapfile -t COMPREPLY < <(compgen -W "${candidates[*]:-}" -- "$cur")
}

complete -f -F _dotnet_bash_complete dotnet

###############################################################################
# Editors
###############################################################################

if command -v nvim >/dev/null 2>&1; then
    export EDITOR='nvim'
    alias vi='nvim'
    alias vim='nvim'
else
    export EDITOR='vim'
fi
export VISUAL="$EDITOR"
command -v code >/dev/null 2>&1 && alias c='code'

###############################################################################
# Other Settings
###############################################################################

shopt -s globstar direxpand autocd checkwinsize cdspell dirspell

command -v bat >/dev/null 2>&1 && export MANPAGER="bat -l man -p"

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init --cmd cd bash)"

command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"

if type __git_complete &>/dev/null; then
    __git_complete g __git_main
fi

bind Space:magic-space
bind '"\eOP": "text-search\n"'

# temporary workaround for Playwright on ubuntu 26.04
export PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64
