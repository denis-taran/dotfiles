Set-StrictMode -Version 3.0

###############################################################################
# Environment
###############################################################################

if (Test-Path -LiteralPath (Join-Path $HOME ".env.ps1")) {
    . (Join-Path $HOME ".env.ps1")
}

$env:GIT_OPTIONAL_LOCKS = "0"

###############################################################################
# Navigation
###############################################################################

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell | Out-String | Invoke-Expression
}

###############################################################################
# Common Aliases
###############################################################################


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

    $status = git status --porcelain=v2 --branch 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }

    $branch = "DETACHED"
    $oid = ""
    $dirty = ""
    $staged = ""
    foreach ($line in $status) {
        if ($line.StartsWith("# branch.head ")) {
            $branch = $line.Substring(14)
        }
        elseif ($line.StartsWith("# branch.oid ")) {
            $oid = $line.Substring(13)
        }
        elseif ($line.StartsWith("1 ") -or $line.StartsWith("2 ")) {
            if ($line[2] -ne '.') { $staged = "+" }
            if ($line[3] -ne '.') { $dirty = "*" }
        }
    }
    if (-not $oid -or $oid -eq "(initial)") { return "" }
    if ($branch -eq "(detached)") { $branch = "DETACHED" }
    return "[$branch@$($oid.Substring(0, 7))$dirty$staged]"
}

function GetSshPrompt {
    if (-not $env:SSH_CONNECTION) {
        return ""
    }

    return "[$env:USERNAME@$env:COMPUTERNAME]"
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

function Format-Colored {
    param([string]$Text, [string]$ColorCode)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $e = [char]27
    return "$e[${ColorCode}m$Text$e[0m"
}

function prompt {
    $lastSuccess = $?
    $sshInfo = GetSshPrompt
    $gitInfo = Get-GitInfo
    $kubeInfo = Get-KubeInfo
    $principal = [Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    $sigil = if ($principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) `
            { '#' } else { '$' }
    $rawPath = (Get-Location).Path
    $homeNorm = $HOME.TrimEnd('\')
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    $atHome = $rawPath.StartsWith($homeNorm, $cmp) -and
              ($rawPath.Length -eq $homeNorm.Length -or
               $rawPath[$homeNorm.Length] -eq '\')
    $loc = if ($atHome) { '~' + $rawPath.Substring($homeNorm.Length) } `
           else { $rawPath }
    $ssh = if ($sshInfo) { (Format-Colored $sshInfo "91") + " " } else { "" }
    $git = if ($gitInfo) { (Format-Colored $gitInfo "94") + " " } else { "" }
    $kube = if ($kubeInfo) { (Format-Colored $kubeInfo "96") + " " } else { "" }
    $path = Format-Colored $loc "92"
    $sigilColor = if ($lastSuccess) { "93" } else { "91" }
    $user = Format-Colored $sigil $sigilColor

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
