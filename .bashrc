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

if [[ -n "$_IS_WSL" ]]; then
    export PATH="/snap/bin:${PATH//:\/snap\/bin/}"
fi

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

export GIT_OPTIONAL_LOCKS=0

[[ $- != *i* ]] && return

###############################################################################
# Common Aliases
###############################################################################

alias g='git'
alias gc='git commit'
alias gcm='git commit -m'
alias gwip='git add -A && git commit -m wip'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias gp='git push'
alias grep='grep --color=auto'
alias showpath='printf "%s\n" "$PATH" | tr ":" "\n"'

if [[ -n "$_IS_WSL" ]]; then
    alias pbcopy='sed "s/\x1B\[[0-9;]*[mK]//g" | clip.exe'
    alias pbpaste='powershell.exe -noprofile -command "Get-Clipboard"'
elif command -v wl-copy >/dev/null 2>&1; then
    alias pbcopy='wl-copy'
    alias pbpaste='wl-paste'
fi

if command -v eza >/dev/null 2>&1; then
    alias lg='eza --git -l --color=always'
    alias ll='eza -lh --color=always'
    alias ls='eza --color=always'
    alias tree='eza --tree --color=always'
fi

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
# Security and SSH
###############################################################################

# TODO: check plugins: https://www.1password.dev/cli/shell-plugins

if [[ -n "$_IS_WSL" ]]; then
    command -v ssh.exe >/dev/null 2>&1 && alias ssh='ssh.exe'
    command -v ssh-add.exe >/dev/null 2>&1 && alias ssh-add='ssh-add.exe'
else
    if [[ -S "$HOME/.1password/agent.sock" ]]; then
        export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
    fi
fi

###############################################################################
# History
###############################################################################

shopt -s histappend

if [[ ! "${HISTTIMEFORMAT@a}" == *r* ]]; then
    export HISTTIMEFORMAT="%F %T "
fi

export HISTCONTROL=ignoreboth
export HISTSIZE=100000
export HISTFILESIZE=200000

###############################################################################
# Kubernetes & Docker/Podman
###############################################################################

export DOCKER_CLI_HINTS="false"

alias k='kubectl'

if command -v podman >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=podman
    export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
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

function clr {
    local -n _out="$1"
    [[ -n "$2" ]] && _out+="\[\033[0;$3\]$2\[\033[0m\]"
}

function git_prompt {
    local d="$PWD" gd=""

    while [[ -n "$d" ]]; do
        if [[ -d "$d/.git" ]]; then gd="$d/.git"; break; fi
        if [[ -f "$d/.git" ]]; then
            read -r gd < "$d/.git"
            if [[ "$gd" == "gitdir: "* ]]; then
                gd="${gd#gitdir: }"
                [[ "$gd" != /* ]] && gd="$d/$gd"
            fi
            break
        fi
        [[ "$d" == "/" ]] && break
        d="${d%/*}"
    done
    [[ -z "$gd" || ! -f "$gd/HEAD" ]] && return

    local head line oid=""
    read -r head < "$gd/HEAD"

    if [[ "$head" != ref:* ]]; then
        _git_prompt_out="[DETACHED@${head:0:7}] "
        return
    fi

    local common_gd="$gd"
    if [[ -f "$gd/commondir" ]]; then
        read -r common_gd < "$gd/commondir"
        [[ "$common_gd" != /* ]] && common_gd="$gd/$common_gd"
    fi

    local branch="${head#ref: refs/heads/}"
    if [[ -f "$common_gd/refs/heads/$branch" ]]; then
        read -r oid < "$common_gd/refs/heads/$branch"
    elif [[ -f "$common_gd/packed-refs" ]]; then
        while read -r line; do
            [[ "$line" == *" refs/heads/$branch" ]] && oid="$line" && break
        done < "$common_gd/packed-refs"
    fi

    local state=""
    if [[ -d "$gd/rebase-merge" || -d "$gd/rebase-apply" ]]; then
        state="|REBASE"
    elif [[ -f "$gd/MERGE_HEAD" ]]; then
        state="|MERGE"
    elif [[ -f "$gd/CHERRY_PICK_HEAD" ]]; then
        state="|CHERRY"
    fi

    if (( ${#branch} > 30 )); then
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
PROMPT_COMMAND+='__prompt_exit=$?; history -a; set_prompt'

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
command -v code >/dev/null 2>&1 && alias c='code'

###############################################################################
# Other Settings
###############################################################################

shopt -s globstar direxpand autocd checkwinsize

command -v bat >/dev/null 2>&1 && export MANPAGER="bat -l man -p"

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

bind '"\eOP": "text-search\n"'

# temporary workaround for Playwright on ubuntu 26.04
export PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64
