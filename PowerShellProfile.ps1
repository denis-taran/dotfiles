
$_nonInteractive = [Environment]::GetCommandLineArgs() |
    Where-Object { $_ -match '^-(NonInteractive|noni|Command|c|File|f|EncodedCommand|e|ec)$' }
if ($_nonInteractive -or -not [Environment]::UserInteractive) {
    return
}

Set-StrictMode -Version 3.0

###############################################################################
# Environment
###############################################################################

if (Test-Path -LiteralPath (Join-Path $HOME ".env.ps1")) {
    . (Join-Path $HOME ".env.ps1")
}

###############################################################################
# Common Aliases
###############################################################################


if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item -Path Alias:ls -Force -ErrorAction SilentlyContinue
    function ll { eza -lh --color=auto @args }
    function ls { eza --color=auto @args }
    function lg { eza --git -l --color=auto @args }
    function tree { eza --tree --color=auto @args }
}

if (-not (Get-Command touch -ErrorAction SilentlyContinue)) {
    function touch { foreach ($f in $args) {
        if (Test-Path $f) { (Get-Item $f).LastWriteTime = Get-Date }
        else { New-Item $f | Out-Null }
    }}
}
function which { (Get-Command $args[0] -ErrorAction SilentlyContinue).Source }
function open { Start-Process $args[0] }
function pbcopy { $input | Set-Clipboard }
function pbpaste { Get-Clipboard }
function showpath { $env:PATH -split [IO.Path]::PathSeparator }

Set-Alias -Name g -Value git
Remove-Item -Path Alias:gc, Alias:gcm, Alias:gl, Alias:gp -Force -ErrorAction SilentlyContinue
function gau { git add -u @args }
function gaa { git add -A @args }
function gap { git add -p @args }
function gc { git commit @args }
function gcm { git commit -m @args }
function gwip { git add -A; git commit -m wip }
function gs { git status @args }
function gd { git diff @args }
function gl { git log --oneline -20 @args }
function gds { git diff --staged @args }
function gp { git push @args }
function gpf { git push --force-with-lease @args }
function gca { git commit --amend @args }
function gcan { git commit --amend --no-edit @args }

function mkcd {
    $Target = New-Item -ItemType Directory -Path $args[0] -Force
    Set-Location -Path $Target.FullName
}

if (Get-Command code -ErrorAction SilentlyContinue) {
    Set-Alias -Name c -Value code
}

###############################################################################
# Project navigation
###############################################################################

function Resolve-Project {
    param([string]$Name, [string]$Worktree)

    $codeDir = Join-Path $HOME "Code"
    if (-not $Name) { Write-Error "project name required"; return $null }

    $pdir = Join-Path $codeDir $Name
    if (-not (Test-Path -LiteralPath $pdir -PathType Container)) {
        Write-Error "Not found: $Name"; return $null
    }

    $porcelain = git -C $pdir worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $porcelain) { return $pdir }

    $trees = @()
    $cur = $null
    foreach ($line in $porcelain) {
        if ($line -like 'worktree *') {
            if ($cur) { $trees += $cur }
            $cur = [ordered]@{
                Path = $line.Substring(9); Branch = ''; Bare = $false
            }
        } elseif ($line -eq 'bare') {
            if ($cur) { $cur.Bare = $true }
        } elseif ($line -like 'branch refs/heads/*') {
            if ($cur) {
                $cur.Branch = $line.Substring('branch refs/heads/'.Length)
            }
        }
    }
    if ($cur) { $trees += $cur }

    if ($trees.Count -le 1) { return $pdir }

    if ($Worktree) {
        $match = $trees |
            Where-Object { $_.Branch -eq $Worktree } |
            Select-Object -First 1
        if (-not $match) {
            Write-Error "Worktree not found: $Worktree"; return $null
        }
        return $match.Path
    }

    $preferred = $trees |
        Where-Object { $_.Branch -eq 'main' } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $trees |
            Where-Object { $_.Branch -eq 'master' } |
            Select-Object -First 1
    }
    if (-not $preferred) {
        $preferred = $trees |
            Where-Object { -not $_.Bare } | Select-Object -First 1
    }
    if (-not $preferred) { $preferred = $trees[0] }
    return $preferred.Path
}

function p {
    param([string]$Project, [string]$Worktree)
    $target = Resolve-Project -Name $Project -Worktree $Worktree
    if ($target) { Set-Location -LiteralPath $target }
}

function pc {
    param([string]$Project, [string]$Worktree)
    $target = Resolve-Project -Name $Project -Worktree $Worktree
    if ($target) { code $target }
}

Register-ArgumentCompleter -CommandName p, pc -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $codeDir = Join-Path $HOME "Code"
    $tokens = $commandAst.CommandElements
    $pos = if ($wordToComplete) { $tokens.Count - 1 } else { $tokens.Count }

    if ($pos -le 1) {
        if (-not (Test-Path -LiteralPath $codeDir)) { return }
        Get-ChildItem -LiteralPath $codeDir -Directory `
                -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name, $_.Name, 'ParameterValue', $_.Name)
            }
    }
    elseif ($pos -eq 2) {
        $proj = $tokens[1].Value
        $pdir = Join-Path $codeDir $proj
        if (-not (Test-Path -LiteralPath $pdir)) { return }
        $porcelain = git -C $pdir worktree list --porcelain 2>$null
        foreach ($line in $porcelain) {
            if ($line -like 'branch refs/heads/*') {
                $br = $line.Substring('branch refs/heads/'.Length)
                if ($br -like "$wordToComplete*") {
                    [System.Management.Automation.CompletionResult]::new(
                        $br, $br, 'ParameterValue', $br)
                }
            }
        }
    }
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
# Prompt
###############################################################################

function Test-GitDirBare {
    param([string]$GitDir)

    $configPath = [IO.Path]::Combine($GitDir, "config")
    if (-not [IO.File]::Exists($configPath)) { return $false }

    $section = ""
    $bare = $false
    foreach ($configLine in [IO.File]::ReadAllLines($configPath)) {
        $line = (($configLine -replace "[#;].*$", "") `
                -replace "\s", "").ToLowerInvariant()
        if ($line -match "^\[.*\]$") {
            $section = $line
        } elseif ($section -eq "[core]" -and $line -eq "bare") {
            $bare = $true
        } elseif ($section -eq "[core]" -and $line.StartsWith("bare=")) {
            $value = $line.Substring(5).Trim([char]34)
            if ($value -in @("true", "yes", "on") -or
                ($value -match "^[+-]?[0-9]+$" -and
                 $value -notmatch "^[+-]?0+$")) {
                $bare = $true
            } else {
                $bare = $false
            }
        }
    }
    return $bare
}

function Get-GitInfo {
    $gitDir = $null
    $gitFile = $false
    if ($PWD.Provider.Name -ne "FileSystem") { return "" }
    for ($d = $PWD.ProviderPath; $d; $d = [IO.Path]::GetDirectoryName($d)) {
        $g = [IO.Path]::Combine($d, ".git")
        if ([IO.Directory]::Exists($g)) { $gitDir = $g; break }
        if ([IO.File]::Exists($g)) {
            $gitFile = $true
            $ref = [IO.File]::ReadAllText($g).Trim()
            if ($ref.StartsWith("gitdir: ")) {
                $resolved = [IO.Path]::Combine(
                    $d, $ref.Substring(8))
                $gitDir = [IO.Path]::GetFullPath(
                    $resolved)
            }
            break
        }
    }
    if (-not $gitDir) { return "" }

    $commondirPath = [IO.Path]::Combine($gitDir, "commondir")
    if ($gitFile -and -not [IO.File]::Exists($commondirPath) -and
        (Test-GitDirBare $gitDir)) {
        return "[hub]"
    }

    $headPath = [IO.Path]::Combine($gitDir, "HEAD")
    if (-not [IO.File]::Exists($headPath)) { return "" }
    $head = [IO.File]::ReadAllText($headPath).Trim()

    $branch = ""
    $oid = ""
    $state = ""
    $rebaseDir = $null

    $rebaseMergeDir = [IO.Path]::Combine($gitDir, "rebase-merge")
    $rebaseApplyDir = [IO.Path]::Combine($gitDir, "rebase-apply")
    if ([IO.Directory]::Exists($rebaseMergeDir)) {
        $state = "|REBASE"
        $rebaseDir = $rebaseMergeDir
    } elseif ([IO.Directory]::Exists($rebaseApplyDir)) {
        $rebaseDir = $rebaseApplyDir
        if ([IO.File]::Exists([IO.Path]::Combine($rebaseDir, "applying"))) {
            $state = "|AM"
        } else {
            $state = "|REBASE"
        }
    } elseif ([IO.File]::Exists([IO.Path]::Combine($gitDir, "MERGE_HEAD"))) {
        $state = "|MERGE"
    } elseif ([IO.File]::Exists(
        [IO.Path]::Combine($gitDir, "CHERRY_PICK_HEAD")
    )) {
        $state = "|CHERRY"
    } elseif ([IO.File]::Exists([IO.Path]::Combine($gitDir, "REVERT_HEAD"))) {
        $state = "|REVERT"
    } elseif ([IO.File]::Exists([IO.Path]::Combine($gitDir, "BISECT_LOG"))) {
        $state = "|BISECT"
    }

    if (-not $head.StartsWith("ref: ")) {
        $oid = $head
        if ($rebaseDir) {
            $headNamePath = [IO.Path]::Combine($rebaseDir, "head-name")
            if ([IO.File]::Exists($headNamePath)) {
                $branch = [IO.File]::ReadAllText($headNamePath).Trim()
                if ($branch.StartsWith("refs/heads/")) {
                    $branch = $branch.Substring(11)
                }
            }
        }
        if (-not $branch -or $branch -eq "detached HEAD") {
            $branch = "DETACHED"
        }
    } else {
        $ref = $head.Substring(5)
        if (-not $ref.StartsWith("refs/")) { return "" }
        $commonGitDir = $gitDir
        if ([IO.File]::Exists($commondirPath)) {
            $rel = [IO.File]::ReadAllText(
                $commondirPath).Trim()
            $commonGitDir = [IO.Path]::GetFullPath(
                [IO.Path]::Combine($gitDir, $rel))
        }

        if ($ref.StartsWith("refs/heads/")) {
            $branch = $ref.Substring(11)
        } else {
            $branch = $ref.Substring(5)
        }
        $lookupRef = $ref
        $depth = 0
        while ($lookupRef -and $depth -lt 8) {
            $refPath = [IO.Path]::Combine($commonGitDir, $lookupRef)
            $worktreeRefPath = [IO.Path]::Combine($gitDir, $lookupRef)
            if ([IO.File]::Exists($worktreeRefPath)) {
                $refPath = $worktreeRefPath
            }
            if (-not [IO.File]::Exists($refPath)) { break }

            $refValue = [IO.File]::ReadAllText($refPath).Trim()
            if ($refValue.StartsWith("ref: refs/")) {
                $lookupRef = $refValue.Substring(5)
                $depth++
            } else {
                if ($refValue -match "^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$") {
                    $oid = $refValue
                }
                $lookupRef = $null
                break
            }
        }
        if ($depth -ge 8) { $lookupRef = $null }

        if (-not $oid -and $lookupRef) {
            $packedPath = [IO.Path]::Combine($commonGitDir, "packed-refs")
            if ([IO.File]::Exists($packedPath)) {
                $suffix = " $lookupRef"
                foreach ($line in [IO.File]::ReadAllLines($packedPath)) {
                    if ($line.EndsWith($suffix)) {
                        $oid = $line.Substring(0, $line.IndexOf(" "))
                        break
                    }
                }
            }
        }
    }

    if ($branch.Length -gt 30) {
        $branch = $branch.Substring(0, 14) +
            [char]0x2026 +
            $branch.Substring($branch.Length - 15)
    }
    if ($oid) {
        $shortOid = $oid.Substring(0, [Math]::Min(7, $oid.Length))
        return "[$branch@$shortOid$state]"
    } else {
        return "[$branch$state]"
    }
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

$_sigil = if (([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent()
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) `
    { '#' } else { '$' }

function prompt {
    $lastSuccess = $?
    $sshInfo = GetSshPrompt
    $gitInfo = Get-GitInfo
    $kubeInfo = Get-KubeInfo
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
    $user = Format-Colored $global:_sigil $sigilColor

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
