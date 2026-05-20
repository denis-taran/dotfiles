Set-StrictMode -Version 3.0

###############################################################################
# Navigation
###############################################################################

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell | Out-String | Invoke-Expression
}

###############################################################################
# Common Aliases
###############################################################################

function touch {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$fileName)
    if (-not (Test-Path $fileName)) { 
        New-Item -ItemType File  -Path $fileName -Force
    }
    else {
        (Get-Item $fileName).LastWriteTime = Get-Date
    }
}

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ll { eza -lh --color=always @args }
    function ls { eza --color=always @args }
    function lg { eza --git -l --color=always @args }
    function tree { eza --tree --color=always @args }
}

function which { (Get-Command $args[0] -ErrorAction SilentlyContinue).Source }
function open { Start-Process $args[0] }
function pbcopy { $input | Set-Clipboard }
function pbpaste { Get-Clipboard }
function showpath { $env:PATH -split [IO.Path]::PathSeparator }

Set-Alias -Name g -Value git

if (Get-Command code -ErrorAction SilentlyContinue) {
    Set-Alias -Name c -Value code
}

$neovimCmd = Get-Command nvim -ErrorAction SilentlyContinue

if ($neovimCmd) {
    Set-Alias vi  $neovimCmd.Source
    Set-Alias vim $neovimCmd.Source
    $env:EDITOR = "nvim"
}

###############################################################################
# Kubernetes & Docker/Podman 
###############################################################################

$env:DOCKER_CLI_HINTS = "false"

if (Get-Command kubectl -ErrorAction SilentlyContinue) { 
    Set-Alias -Name k  -Value kubectl
}

if (Get-Command podman -ErrorAction SilentlyContinue) {
    $env:KIND_EXPERIMENTAL_PROVIDER = "podman"
    Set-Alias -Name d -Value podman
}
elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    $env:KIND_EXPERIMENTAL_PROVIDER = "docker"
    Set-Alias -Name d -Value docker
}
else {
    Remove-Item Env:KIND_EXPERIMENTAL_PROVIDER `
        -ErrorAction SilentlyContinue
}

function kube_info {
    $env:DISPLAY_KUBE_INFO = "1"
}

function disable_kube_info {
    Remove-Item Env:DISPLAY_KUBE_INFO -ErrorAction SilentlyContinue 
}

###############################################################################
# 1Password
###############################################################################

$opPlugins = Join-Path $HOME ".config\op\plugins.ps1"
if (Test-Path $opPlugins) { . $opPlugins }

###############################################################################
# Prompt
###############################################################################

function Get-GitInfo {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return "" }

    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return "" }

    $branch = git symbolic-ref --quiet --short HEAD 2>$null
    if (-not $branch) {
        $branch = "DETACHED"
    }

    $commit = git rev-parse --short HEAD 2>$null
    if ($commit) {
        return "[$branch@$commit]"
    }
    return ""
}

function GetSshPrompt {
    if (-not $env:SSH_CONNECTION) {
        return ""
    }

    $parts = $env:SSH_CONNECTION -split ' ', 2
    if ($parts[0]) {
        return "[$($parts[0])]"
    }

    return ""
}

function Get-KubeInfo {
    if (-not $env:DISPLAY_KUBE_INFO) { return "" }
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { return "" }
    $raw = kubectl config view --minify `
        --output 'jsonpath={.current-context}{"\n"}{..namespace}' 2>$null
    if (-not $raw) { return "" }
    $parts = $raw -split "`n", 2
    $ctx = $parts[0]
    if (-not $ctx) { return "" }
    $ns = if ($parts.Count -gt 1 -and $parts[1]) `
        { $parts[1] } else { "default" }
    return "[${ctx}:${ns}]"
}

function prompt {
    $sshInfo = GetSshPrompt
    $gitInfo = Get-GitInfo
    $kubeInfo = Get-KubeInfo
    $principal = [Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    $sigil = if ($principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) `
            { '#' } else { '$' }
    $loc = (Get-Location).Path -ireplace "^$([regex]::Escape($HOME))", '~'
    $ssh = if ($sshInfo) {
        "$($PSStyle.Foreground.BrightRed)$sshInfo$($PSStyle.Reset) "
    } else { "" }
    $git = if ($gitInfo) {
        "$($PSStyle.Foreground.BrightBlue)$gitInfo$($PSStyle.Reset) "
    } else { "" }
    $kube = if ($kubeInfo) {
        "$($PSStyle.Foreground.BrightCyan)$kubeInfo$($PSStyle.Reset) "
    } else { "" }
    $path = "$($PSStyle.Foreground.BrightGreen)$loc$($PSStyle.Reset)"
    $user = "$($PSStyle.Foreground.BrightYellow)$sigil$($PSStyle.Reset)"

    return "$ssh$git$kube$path $user "
}

###############################################################################
# Bash-like keybindings
###############################################################################

Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistoryNoDuplicates:$true
Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true 

###############################################################################
# .NET
###############################################################################

# copied from official Microsoft dotnet powershell documentation 
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" |
            ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_)
        }
}