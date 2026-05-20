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

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

[[ $- != *i* ]] && return

###############################################################################
# Common Aliases
###############################################################################

alias g='git'
alias grep='grep --color=auto'
alias showpath='printf "%s\n" "$PATH" | tr ":" "\n"'

if grep -qi microsoft /proc/version 2>/dev/null; then
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
# Bash Completion
###############################################################################

if [[ -r /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/bash_completion
fi

###############################################################################
# Security and SSH
###############################################################################

# TODO: check plugins: https://www.1password.dev/cli/shell-plugins

if grep -qi microsoft /proc/version 2>/dev/null; then
    command -v ssh.exe >/dev/null 2>&1 && alias ssh='ssh.exe'
    command -v ssh-add.exe >/dev/null 2>&1 && alias ssh-add='ssh-add.exe'
    command -v op.exe >/dev/null 2>&1 && alias op='op.exe'
else
    export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
fi

###############################################################################
# History
###############################################################################

shopt -s histappend

export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=ignoreboth
export HISTSIZE=1000
export HISTFILESIZE=2000

###############################################################################
# Kubernetes & Docker/Podman
###############################################################################

export DOCKER_CLI_HINTS="false"

alias k='kubectl'

if command -v podman >/dev/null 2>&1; then
    export KIND_EXPERIMENTAL_PROVIDER=podman
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

[[ -x "/snap/aws-cli/current/bin/aws_completer" ]] &&
    complete -C "/snap/aws-cli/current/bin/aws_completer" aws

# shellcheck source=/dev/null
[[ -r "$HOME/lib/azure-cli/az.completion" ]] &&
    . "$HOME/lib/azure-cli/az.completion"

###############################################################################
# Prompt
###############################################################################

function clr {
    local text="$1"
    local color_code="$2"
    [[ -n "$text" ]] && echo -e "\[\033[0;$color_code\]$text\[\033[0m\]"
}

function git_prompt {
    local gdir="$1"
    [[ -z "$gdir" ]] && return
    local branch commit
    branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
    [[ -z "$branch" ]] && branch="DETACHED"
    commit=$(git rev-parse --short HEAD 2>/dev/null)
    [[ -n "$commit" ]] && echo "[$branch@$commit] "
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
    echo "[$ctx:$ns] "
}

function set_prompt {
    local exit_status=$?

    local gdir ip
    gdir=$(git rev-parse --absolute-git-dir 2>/dev/null)
    [[ -n "$SSH_CONNECTION" ]] && ip="${SSH_CONNECTION%% *}"

    local git kube ssh uchar
    git=$(git_prompt "$gdir")
    kube=$(kube_prompt)
    [[ -n "$ip" ]] && ssh="[$ip] "
    [[ $EUID -eq 0 ]] && uchar="#" || uchar="$"

    local pwd_str="${PWD/#$HOME/\~}"
    PS1="$(clr "$ssh" "91m")$(clr "$git" "94m")"
    PS1+="$(clr "$kube" "96m")$(clr "$pwd_str" "92m") $(clr "$uchar" "93m") "

    return "$exit_status"
}

PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND%;}; }set_prompt"

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

export DOTNET_ROOT="$HOME/.dotnet"
path_prepend "$HOME/.dotnet/tools"
path_prepend "$HOME/.dotnet"

###############################################################################
# Editors
###############################################################################

export EDITOR='nvim'

alias c='code'
alias vi='nvim'
alias vim='nvim'

###############################################################################
# Other Settings
###############################################################################

shopt -s globstar direxpand autocd checkwinsize

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
