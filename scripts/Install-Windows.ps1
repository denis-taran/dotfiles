
$ErrorActionPreference = "Stop"

$scriptPath = $MyInvocation.MyCommand.Definition
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$CanSymlink = $IsAdmin -or (
    (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1
)
$CanEditRegistry = & {
    $testPath = 'HKCU:\Software\_RegistryWriteTest'
    try {
        New-Item -Path $testPath -Force -ErrorAction Stop | Out-Null
        Remove-Item -Path $testPath -Force -ErrorAction SilentlyContinue
        $true
    } catch {
        $false
    }
}
if (-not $CanEditRegistry) {
    Write-Warning "Registry editing is disabled by policy. Registry settings will be skipped."
}
if (-not $IsAdmin) {
    Write-Warning "The script is running without administrator privileges, so certain settings will be skipped."
}
if (-not $CanSymlink) {
    Write-Warning "The dotfiles will be copied instead of being linked because symlinks are unavailable."
}

$RepoRoot = Split-Path -Path (Split-Path -Path $scriptPath -Parent) -Parent

function Set-Link($TargetPath, $LinkPath) {
    if (-not (Test-Path $TargetPath)) {
        throw "missing target: $TargetPath"
    }

    $TargetPath = (Resolve-Path $TargetPath).Path

    if (Test-Path -LiteralPath $LinkPath) {
        $existing = Get-Item -LiteralPath $LinkPath -Force
        if ($existing.LinkType -ne 'SymbolicLink' -and
            $existing.LinkType -ne 'Junction') {
            if ($CanSymlink) {
                throw "refusing to replace real path at '$LinkPath'"
            }
            Backup-File $LinkPath
        } elseif ($existing.LinkType -eq 'SymbolicLink' -and
            $existing.Target -eq $TargetPath) {
            return
        }
        Remove-Item -LiteralPath $LinkPath -Force -Recurse
    }

    $dir = Split-Path $LinkPath
    if ($dir) { New-Item $dir -ItemType Directory -Force | Out-Null }

    if ($CanSymlink) {
        New-Item -ItemType SymbolicLink `
            -Path $LinkPath `
            -Target $TargetPath `
            -Force | Out-Null
    } else {
        Copy-Item -LiteralPath $TargetPath -Destination $LinkPath -Force
    }
}

function Install-DotFiles() {
    $vsSettings = Resolve-Path `
        "$env:LOCALAPPDATA\Microsoft\VisualStudio\[0-9]*\settings.json" `
        -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path |
        Sort-Object |
        Select-Object -Last 1

    if ($vsSettings) {
        Set-Link -LinkPath $vsSettings -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\vs\settings.json')
    }

    Set-Link -LinkPath "$Env:APPDATA\Code\User\settings.json" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\Code\User\settings.json')
    Set-Link -LinkPath "$Env:UserProfile/.config/git/attributes" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\git\attributes')
    Set-Link -LinkPath "$Env:UserProfile/.config/git/ignore" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\git\ignore')
    Set-Link -LinkPath "$Env:UserProfile/.config/git/config" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\git\config')
    Set-Link -LinkPath "$Env:UserProfile/.editorconfig" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.editorconfig')
    Set-Link -LinkPath "$Env:LOCALAPPDATA\nvim\init.lua" -TargetPath (Join-Path -Path $RepoRoot -ChildPath '.config\nvim\init.lua')
}

function Set-GitLocalConfig() {
    $gitLocalConfig = Join-Path -Path $Env:UserProfile -ChildPath '.config\git\local'
    $allowedSigners = Join-Path -Path $Env:UserProfile -ChildPath '.config\git\allowed_signers'
    $opSshSign = Join-Path -Path $Env:LOCALAPPDATA -ChildPath `
        'Microsoft\WindowsApps\op-ssh-sign.exe'

    $curName = git config -f $gitLocalConfig user.name 2>$null
    $curEmail = git config -f $gitLocalConfig user.email 2>$null
    $curKey = git config -f $gitLocalConfig user.signingkey 2>$null

    $gitName = $curName
    $gitEmail = $curEmail
    if (-not $curName) { $gitName = Read-Host "Git full name" }
    if (-not $curEmail) { $gitEmail = Read-Host "Git email" }

    $keyLine = $null
    if (-not $curKey) {
        $keyLine = (Read-Host `
            "SSH public key for commit signing (blank to skip)").Trim()
        if ($keyLine -and $keyLine -notmatch '^ssh-') {
            throw "not an SSH public key (must start with ssh-)"
        }
    }

    New-Item -Path (Split-Path $gitLocalConfig -Parent) -ItemType Directory -Force | Out-Null

    if (-not $curName) {
        git config -f $gitLocalConfig user.name $gitName
    }

    if (-not $curEmail) {
        git config -f $gitLocalConfig user.email $gitEmail
    }

    if (-not $curKey -and $keyLine) {
        git config -f $gitLocalConfig user.signingkey $keyLine
        git config -f $gitLocalConfig commit.gpgsign true
        git config -f $gitLocalConfig gpg.format ssh
        git config -f $gitLocalConfig `
            gpg.ssh.allowedSignersFile $allowedSigners
        Backup-File $allowedSigners
        [System.IO.File]::WriteAllText($allowedSigners, "$gitEmail $keyLine`n", [System.Text.UTF8Encoding]::new($false))
    }

    $sysRoot = $env:SystemRoot -replace '\\', '/'
    git config -f $gitLocalConfig core.sshCommand "$sysRoot/System32/OpenSSH/ssh.exe"
    git config -f $gitLocalConfig gpg.ssh.program $opSshSign
}

function Install-Apps() {
    $applications = @(
        "AgileBits.1Password.CLI",
        "AgileBits.1Password",
        "ajeetdsouza.zoxide",
        "Amazon.AWSCLI",
        "dotPDN.PaintDotNet",
        "Git.Git",
        "Microsoft.AzureCLI",
        "Microsoft.Coreutils",
        "Microsoft.DotNet.SDK.10",
        "Microsoft.PowerShell",
        "Microsoft.VisualStudioCode",
        "Neovim.Neovim",
        "Obsidian.Obsidian",
        "ONLYOFFICE.DesktopEditors",
        "OpenJS.NodeJS.LTS",
        "Python.Python.3.14",
        "Tailscale.Tailscale"
    )

    foreach ($appId in $applications) {
        $installArgs = @(
            'install',
            '--id', $appId,
            '--exact',
            '--source', 'winget',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )

        Write-Host "install '$appId'"
        & winget @installArgs
    }
}

function Uninstall-Preinstalled-Apps() {
    $uninstall = @(
        "*AdobePhotoshopExpress*",
        "*BingNews*",
        "*BingSearch*",
        "*BingWeather*",
        "*Clipchamp*",
        "*DolbyAccess*",
        "*Instagram*",
        "*LinkedIn*",
        "*MicrosoftOfficeHub*",
        "*Microsoft.OutlookForWindows*",
        "*Microsoft.PowerAutomateDesktop*",
        "*MicrosoftPowerBIForWindows*",
        "*MicrosoftSolitaireCollection*",
        "*Microsoft.Windows.DevHome*",
        "*Microsoft.Xbox.TCUI*",
        "*Microsoft.XboxGameOverlay*",
        "*Microsoft.XboxGamingOverlay*",
        "*Microsoft.XboxIdentityProvider*",
        "*Microsoft.XboxSpeechToTextOverlay*",
        "*Microsoft.YourPhone*",
        "*Netflix*",
        "*SkypeApp*",
        "*Spotify*",
        "*TikTok*",
        "*Twitter*",
        "*WebExperience*"
    )

    $installedPackages = Get-AppxPackage -PackageTypeFilter Main, Bundle
    $provisionedOutput = & dism.exe /Online /Get-ProvisionedAppxPackages 2>&1
    $provisionedPackages = foreach ($line in $provisionedOutput) {
        if ($line -match '^\s*PackageName\s*:\s*(.+)$') {
            $matches[1].Trim()
        }
    }

    foreach ($package in $uninstall) {
        $packagesToRemove = $installedPackages |
        Where-Object {
            $_.Name -like $package -or
            $_.PackageFamilyName -like $package -or
            $_.PackageFullName -like $package
        } |
        Group-Object PackageFamilyName

        foreach ($packageGroup in $packagesToRemove) {
            $candidate = $packageGroup.Group |
            Where-Object { $_.PackageFullName -like '*_~_*' } |
            Select-Object -First 1

            if (-not $candidate) {
                $candidate = $packageGroup.Group | Select-Object -First 1
            }

            try {
                Remove-AppxPackage -Package $candidate.PackageFullName
            }
            catch {
                Write-Warning "failed to remove '$($candidate.PackageFullName)': $($_.Exception.Message)"
            }
        }

        foreach ($packageName in $provisionedPackages | Where-Object { $_ -like $package }) {
            try {
                & dism.exe /Online /Remove-ProvisionedAppxPackage "/PackageName:$packageName" /NoRestart 2>&1
            }
            catch {
                Write-Warning "failed to remove provisioned '$packageName': $($_.Exception.Message)"
            }
        }
    }
}

function Disable-Services() {
    $services = @(
        "DiagTrack",
        "XboxGipSvc",
        "XblAuthManager",
        "RemoteRegistry",

        # disable the built-in OpenSSH agent from MS, so that 1Password can provide the
        # SSH agent used by the Windows OpenSSH, Git and ssh.exe programs.
        "ssh-agent"
    )

    foreach ($service in $services) {
        if (Get-Service $service -ErrorAction SilentlyContinue) {
            Set-Service $service -StartupType Disabled
            Stop-Service $service -Force -ErrorAction SilentlyContinue
        }
    }
}

function Disable-WindowsFeatures() {
    & dism.exe /Online /Disable-Feature `
        /FeatureName:WindowsMediaPlayer /NoRestart /Quiet | Out-Null

    & dism.exe /Online /Disable-Feature `
        /FeatureName:SMB1Protocol /NoRestart /Quiet | Out-Null
}

function Set-SecurityBaseline() {
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v EnableMulticast /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 1 /f
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 1 /f

    $netbiosFailures = @()
    Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $null -ne $_.TcpipNetbiosOptions } |
        ForEach-Object {
            $result = Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 }
            if ($result.ReturnValue -ne 0) {
                $netbiosFailures += "$($_.Description) (code $($result.ReturnValue))"
            }
        }
    if ($netbiosFailures.Count -gt 0) {
        Write-Warning "NetBIOS disable failed on: $($netbiosFailures -join ', ')"
    }

    $psLogPaths = @(
        "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell",
        "HKLM\SOFTWARE\Policies\Microsoft\PowerShellCore"
    )
    foreach ($base in $psLogPaths) {
        REG ADD "$base\ScriptBlockLogging" /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f
        REG ADD "$base\ModuleLogging" /v EnableModuleLogging /t REG_DWORD /d 1 /f
        REG ADD "$base\ModuleLogging\ModuleNames" /v "*" /t REG_SZ /d "*" /f
    }
}

function Set-PowerManagement() {
    powercfg /hibernate on
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 1800
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 18000
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONNECTIVITYINSTANDBY 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONNECTIVITYINSTANDBY 0
    powercfg /setactive SCHEME_CURRENT

    $wakeDevices = powercfg -devicequery wake_armed
    foreach ($device in $wakeDevices) {
        if (![string]::IsNullOrWhiteSpace($device)) {
            powercfg -devicedisablewake "$device"
        }
    }

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" /v ShowHibernateOption /t REG_DWORD /d 1 /f
    Write-Host "power settings updated" -ForegroundColor Green
}

function Set-Keyboard() {
    if (-not $CanEditRegistry) { return }
    # 0 = shortest, 3 = longest
    $desiredValue = 0

    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value $desiredValue
    if ($IsAdmin) {
        REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout" /V "Scancode Map" /T REG_BINARY /D "000000000000000002000000000052e000000000" /F
    }
    REG ADD "HKCU\Control Panel\Accessibility\StickyKeys" /V "Flags" /T REG_SZ /D "26" /F

    if (-not ([System.Management.Automation.PSTypeName]'RefreshSystemSettings').Type) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;

        public class RefreshSystemSettings {
            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo(int uAction, int uParam, IntPtr lpvParam, int fuWinIni);
        }
"@
    }

    $SPI_SETKEYBOARDDELAY = 0x0017
    $SPIF_UPDATEINIFILE = 0x0001
    $SPIF_SENDCHANGE = 0x0002
    [RefreshSystemSettings]::SystemParametersInfo($SPI_SETKEYBOARDDELAY, $desiredValue, [System.IntPtr]::Zero, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)
}

function Set-NoSoundScheme {
    if (-not $CanEditRegistry) { return }
    $SoundSchemePath = "HKCU:\AppEvents\Schemes"
    $KeyName = "(Default)"
    $NoSoundValue = ".None"

    Write-Host "`nsound scheme -> no sound" -ForegroundColor Cyan

    if (-not (Test-Path $SoundSchemePath)) {
        New-Item -Path $SoundSchemePath -Force | Out-Null
    }

    $CurrentValue = (Get-ItemProperty -Path $SoundSchemePath -Name $KeyName -ErrorAction SilentlyContinue).$KeyName

    if ($CurrentValue -eq $NoSoundValue) {
        Write-Host "no sound already set" -ForegroundColor Green
    }
    else {
        New-ItemProperty -Path $SoundSchemePath -Name $KeyName -Value $NoSoundValue -Force | Out-Null

        Get-ChildItem -Path "$SoundSchemePath\Apps" -Recurse |
        Where-Object { $_.PSChildName -eq ".Current" } |
        Set-ItemProperty -Name "(Default)" -Value "" -Force

        Write-Host "no sound applied" -ForegroundColor Green
    }
}

function Set-WindowsSecurity() {
    $null = New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "BlockUserFromShowingAccountDetailsOnSignin" -Value 1 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "NoLocalPasswordResetQuestions" -Value 1 -Type DWord
}

function Set-DeveloperSettings() {
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo" /V "Enabled" /T REG_DWORD /D 1 /F
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo" /V "Mode" /T REG_DWORD /D 2 /F
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /T REG_DWORD /F /V "AllowDevelopmentWithoutDevLicense" /D "1"
}

function Set-EdgeSettings() {
    $edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    $null = New-Item -Path $edgePol -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePol -Name RestoreOnStartup -Value 4 -Type DWord -Force
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /V HomepageLocation /T REG_SZ /D "about:blank" /F
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v RestoreOnStartupURLs /t REG_MULTI_SZ /d "about:blank" /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v HomepageIsNewTabPage /t REG_DWORD /d 0 /f
    Set-ItemProperty -Path $edgePol -Name NewTabPageLocation -Value "about:blank" -Type String -Force
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v NewTabPageContentEnabled /t REG_DWORD /d 0 /f

    Remove-ItemProperty -Path $edgePol -Name DefaultSearchProviderEnabled -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $edgePol -Name DefaultSearchProviderSearchURL -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $edgePol -Name DefaultSearchProviderKeyword -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $edgePol -Name DefaultSearchProviderSuggestURL -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $edgePol -Name DefaultSearchProviderName -ErrorAction SilentlyContinue

    $managedEngines = '[{"is_default":true,"name":"Google","keyword":"google.com","search_url":"https://www.google.com/search?q={searchTerms}","suggest_url":"https://www.google.com/complete/search?output=chrome&q={searchTerms}","favicon_url":"https://www.google.com/favicon.ico","encoding":"UTF-8"}]'
    Set-ItemProperty -Path $edgePol -Name "ManagedSearchEngines" -Value $managedEngines -Type String -Force

    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /V NewTabPageSearchBox /T REG_SZ /D "redirect" /F
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /V AutofillCreditCardEnabled /T REG_dWORD /D 0 /F
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v SeamlessWebToBrowserSignInEnabled /t REG_DWORD /d 0 /f
    Set-ItemProperty -Path $edgePol -Name PasswordAutofillEnabled -Value 0 -Type DWord -Force
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v PasswordManagerEnabled /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v AutofillAddressEnabled /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v WebToBrowserSignInEnabled /t REG_DWORD /d 0 /f

    Set-ItemProperty -Path $edgePol -Name BrowserSignin -Value 0 -Type DWord -Force
}

function Disable-Copilot() {
    if (-not $CanEditRegistry) { return }
    reg add "HKCU\Software\Microsoft\input\Settings" /v InsightsEnabled /t REG_DWORD /d 0 /f
    if ($IsAdmin) {
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v SettingsPageVisibility /t REG_SZ /d "hide:aicomponents;" /f
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v CopilotCDPPageContext /t REG_DWORD /d 0 /f
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v CopilotPageContext /t REG_DWORD /d 0 /f
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v HubsSidebarEnabled /t REG_DWORD /d 0 /f
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v AutoOpenCopilotLargeScreens /t REG_DWORD /d 0 /f
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI" /v Value /t REG_SZ /d Deny /f
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsAccessGenerativeAI /t REG_DWORD /d 2 /f
    }
}

function Set-RegionalFormat() {
    if (-not $CanEditRegistry) { return }
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortTime -Value HH:mm
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sTimeFormat -Value HH:mm:ss
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sShortDate -Value yyyy-MM-dd
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name iFirstDayOfWeek -Value 0
    Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name sLongDate -Value "dddd, MMMM dd, yyyy"
}

function Set-ExplorerSettings() {
    if (-not $CanEditRegistry) { return }
    REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /V "ShowRecent" /T REG_DWORD /D 0 /F
    REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /V "ShowFrequent" /T REG_DWORD /D 0 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /V HideFileExt /T REG_dWORD /D 0 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /V LaunchTo /T REG_dWORD /D 1 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoComplete" /V AutoSuggest /T REG_SZ /D no /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /V ShowInfoTip /T REG_dWORD /D 0 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /V ShowSyncProviderNotifications /T REG_dWORD /D 0 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /V "UseCompactMode" /T REG_DWORD /D "1" /F
    if ($IsAdmin) {
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /V DisableSearchBoxSuggestions /T REG_dWORD /D 1 /F
        $null = New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Name "{6767B3BC-8FF7-11EC-B909-0242AC120002}" -Value "" -Type String -Force
        REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v MultiTaskingAltTabFilter /t REG_DWORD /d 3 /f
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" -Name "{E2BF9676-5F8F-435C-97EB-11607A5BEDF7}" -Value "" -Type String -Force
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /V HideRecentlyAddedApps /T REG_dWORD /D 1 /F
    }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2
}

function Disable-ConnectivityFeatures() {
    REG ADD "HKLM\SOFTWARE\Microsoft\WcmSvc\Tethering" /V RemoteStartupDisabled /T REG_dWORD /D 1 /F
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\Connect" /V AllowProjectionToPC /T REG_dWORD /D 0 /F
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /V EnableCdp /T REG_dWORD /D 0 /F
}

function Set-ThemeSettings() {
    if (-not $CanEditRegistry) { return }
    REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /V SystemUsesLightTheme /T REG_DWORD /D 0 /F
    REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /V AppsUseLightTheme /T REG_DWORD /D 0 /F
}

function Set-StorageSettings() {
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /V AllowStorageSenseGlobal /T REG_dWORD /D 0 /F
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /V ConfigStorageSenseDownloadsCleanupThreshold /T REG_dWORD /D 0 /F
}

function Set-NotificationSettings() {
    if (-not $CanEditRegistry) { return }
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /V NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND /T REG_dWORD /D 0 /F
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /V NOC_GLOBAL_SETTING_BADGE_ENABLED /T REG_dWORD /D 1 /F
}

function Enable-LocationAndTz() {
    REG ADD "HKLM\Software\Policies\Microsoft\Windows\LocationAndSensors" /v DisableLocation /t REG_DWORD /d 0 /f
    REG ADD "HKLM\Software\Policies\Microsoft\Windows\LocationAndSensors" /v DisableLocationScripting /t REG_DWORD /d 0 /f
    REG ADD "HKLM\Software\Policies\Microsoft\Windows\LocationAndSensors" /v DisableSensors /t REG_DWORD /d 0 /f
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsAccessLocation /t REG_DWORD /d 1 /f
    REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v DisableAutoTimeZoneUpdate /t REG_DWORD /d 0 /f
    REG ADD "HKLM\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v Value /t REG_SZ /d Allow /f
    REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate" /v Start /t REG_DWORD /d 3 /f
}

function Set-UIAnimations() {
    if (-not $CanEditRegistry) { return }
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WindowAnimation" -Value 0
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value 0
}

function Register-NugetSource() {
    if (-not (Get-Command dotnet.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "dotnet not found. Skipping NuGet source setup."
        return
    }

    $sources = & dotnet.exe nuget list source 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "unable to list NuGet sources"
    }

    if ($sources | Select-String -Pattern '^\s*\d+\.\s+nuget\.org\b') {
        Write-Host "nuget.org source already present" -ForegroundColor Yellow
        return
    }

    dotnet nuget add source "https://api.nuget.org/v3/index.json" -n "nuget.org"
}

function Set-LockScreenSettings() {
    if (-not $CanEditRegistry) { return }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord
    $lockPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen"
    $null = New-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $lockPath -Name "LockScreenAppId" -Value "" -Type String -Force
    REG ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /V NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK /T REG_dWORD /D 0 /F
}

function Disable-ContentDelivery() {
    if (-not $CanEditRegistry) { return }
    REG ADD "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_dWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_dWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_dWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"  /v SubscribedContent-353694Enabled /t REG_dWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_dWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_dWORD /d 0 /f
    REG ADD "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\CloudContent" /V "DisableThirdPartySuggestions" /T REG_DWORD /D 1 /F
    if ($IsAdmin) {
        REG ADD "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f
        REG ADD "HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /V AllowOnlineTips /T REG_dWORD /D 0 /F
        REG ADD "HKLM\Software\Policies\Microsoft\Windows\CloudContent" /V "DisableWindowsSpotlightFeatures" /T "REG_DWORD" /D "1" /F
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /V DisableSoftLanding /T REG_dWORD /D 1 /F
    }
}

function Set-PowerShellProfile() {
    $customProfilePath = Join-Path -Path $RepoRoot -ChildPath 'PowerShellProfile.ps1'
    $defaultProfilePath = $PROFILE
    if ($CanSymlink) {
        Set-Link -TargetPath $customProfilePath -LinkPath $defaultProfilePath
    } else {
        $dir = Split-Path $defaultProfilePath
        if ($dir) { New-Item $dir -ItemType Directory -Force | Out-Null }
        Backup-File $defaultProfilePath
        [System.IO.File]::WriteAllText($defaultProfilePath, ". '$customProfilePath'`n", [System.Text.UTF8Encoding]::new($false))
    }
}

function Set-PowerShellSettings() {
    [Environment]::SetEnvironmentVariable("POWERSHELL_UPDATECHECK", "Off", "User")
}

function Invoke-PerformanceTweak {
    fsutil behavior set DisableLastAccess 1
    fsutil 8dot3name set C: 1
    attrib +I "$Env:UserProfile\Code" /S /D
}

function Enable-Virtualization() {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $isHyperV = $bios -and
        $bios.Manufacturer -match 'Microsoft Corporation' -and
        $bios.Description -match 'Virtual Machine'
    if (-not $isHyperV) {
        & dism.exe /Online /Enable-Feature `
            /FeatureName:VirtualMachinePlatform /All /NoRestart `
            /Quiet | Out-Null

        & dism.exe /Online /Enable-Feature `
            /FeatureName:Microsoft-Hyper-V /All /NoRestart `
            /Quiet | Out-Null
    }
}

function Set-PrivacySettings() {
    if (-not $CanEditRegistry) { return }
    REG ADD "HKCU\Software\Policies\Microsoft\Windows\CloudContent" /V DisableTailoredExperiencesWithDiagnosticData /T REG_dWORD /D 1 /F
    if ($IsAdmin) {
        REG ADD "HKLM\Software\Policies\Microsoft\Windows\System" /V AllowCrossDeviceClipboard /T REG_DWORD /D 0 /F
        $null = New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Force -ErrorAction SilentlyContinue
        $null = New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord -Force
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /V DisableTailoredExperiencesWithDiagnosticData /T REG_dWORD /D 1 /F
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /V AllowTelemetry /T REG_dWORD /D 0 /F
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_dWORD /d 0 /f
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput" /V AllowLinguisticDataCollection /T REG_dWORD /D 0 /F
        REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /V TailoredExperiencesWithDiagnosticDataEnabled /T REG_dWORD /D 0 /F
        REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /V Start /T REG_dWORD /D 4 /F
        REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /V DoNotShowFeedbackNotifications /T REG_dWORD /D 1 /F
        REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /V DisableDiagnosticDataViewer /T REG_dWORD /D 1 /F
        REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" /V SubmitSamplesConsent /T REG_dWORD /D 2 /F
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_dWORD /d 1 /f
    }

    # electron pwd managers can't use the flag in windows API that keeps passwords
    # out of clipboard history. bitwarden has been dragging this out for years now:
    # https://github.com/bitwarden/clients/issues/2621
    # switched to 1password which has a native interop for that, so no longer needed
    # Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 0 -Type DWord -Force
}

function Set-WindowsUpdateSettings {
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v AUOptions /t REG_DWORD /d 4 /f
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f
    REG ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /V AllowAutoWindowsUpdateDownloadOverMeteredNetwork /T REG_dWORD /D 0 /F
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /V DODownloadMode /T REG_dWORD /D 100 /F
}

function Set-XdgPaths() {
    [Environment]::SetEnvironmentVariable(
        "XDG_CONFIG_HOME",
        (Join-Path $env:USERPROFILE ".config"),
        "User")
    [Environment]::SetEnvironmentVariable(
        "XDG_DATA_HOME",
        (Join-Path $env:USERPROFILE ".local\share"),
        "User")
    [Environment]::SetEnvironmentVariable(
        "XDG_CACHE_HOME",
        (Join-Path $env:USERPROFILE ".cache"),
        "User")
    [Environment]::SetEnvironmentVariable(
        "XDG_STATE_HOME",
        (Join-Path $env:USERPROFILE ".local\state"),
        "User")
}

function Backup-File($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH-mm-ss"
    $backupDir = Join-Path $HOME "Backups\Windows"
    New-Item $backupDir -ItemType Directory -Force | Out-Null
    $backupName = "$ts - $(Split-Path $Path -Leaf)"
    Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir $backupName) -Force
}

function Backup-Registry() {
    $ts = Get-Date -Format "yyyy-MM-dd HH-mm-ss"
    $backupDir = Join-Path $HOME "Backups\Windows\$ts - Registry"
    New-Item $backupDir -ItemType Directory -Force | Out-Null
    Write-Host "Backing up registry to $backupDir ..."
    reg export HKCU "$backupDir\HKCU.reg" /y
    if ($IsAdmin) {
        reg export HKLM "$backupDir\HKLM.reg" /y
    }
}

Write-Warning @"
This script will make destructive and irreversible changes to this machine,
including deleting apps, mutating hundreds of registry keys and disabling services.
"@
$confirm = Read-Host "Type 'yes' to continue or anything else to abort."
if ($confirm -ne 'yes') {
    Write-Host "Aborted."
    exit
}

Backup-Registry
Install-DotFiles
if ($IsAdmin) { Install-Apps }
Set-GitLocalConfig
Set-Keyboard
Set-NoSoundScheme
Disable-Copilot
Set-RegionalFormat
Set-ExplorerSettings
Set-ThemeSettings
Set-NotificationSettings
Set-UIAnimations
Register-NugetSource
Set-LockScreenSettings
Disable-ContentDelivery
Set-PowerShellProfile
Set-PowerShellSettings
Set-PrivacySettings
Set-XdgPaths

if ($IsAdmin) {
    Uninstall-Preinstalled-Apps
    Disable-Services
    Disable-WindowsFeatures
    Set-SecurityBaseline
    Set-PowerManagement
    Set-WindowsSecurity
    Set-DeveloperSettings
    Set-EdgeSettings
    Disable-ConnectivityFeatures
    Set-StorageSettings
    Enable-LocationAndTz
    Invoke-PerformanceTweak
    Enable-Virtualization
    Set-WindowsUpdateSettings
}

Read-Host "`nPress Enter to continue..."