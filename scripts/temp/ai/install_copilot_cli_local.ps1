[CmdletBinding()]
param(
    [ValidateSet('auto', 'winget', 'npm')]
    [string]$Method = 'auto',

    [switch]$Prerelease,

    [switch]$SkipVersionCheck,

    [switch]$SkipLoginReminder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-CopilotCommand {
    $winGetPackageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $winGetPackageRoot) {
        $realExe = Get-ChildItem -LiteralPath $winGetPackageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'GitHub.Copilot_*' } |
            Select-Object -First 1 |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter 'copilot.exe' -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName
            }

        if ($realExe -and (Test-Path -LiteralPath $realExe)) {
            return $realExe
        }
    }

    $commandCandidates = @(Get-Command copilot -ErrorAction SilentlyContinue)
    foreach ($command in $commandCandidates) {
        foreach ($propertyName in 'Path', 'Source', 'Definition') {
            $property = $command.PSObject.Properties[$propertyName]
            if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $candidate = [string]$property.Value
                if ($candidate -match '\.ps1$') {
                    continue
                }

                return $candidate
            }
        }
    }

    if (Test-Command -Name npm) {
        $npmPrefix = (npm prefix -g).Trim()
        foreach ($candidate in @(
            (Join-Path $npmPrefix 'copilot.cmd'),
            (Join-Path $npmPrefix 'copilot'),
            (Join-Path $npmPrefix 'node_modules\.bin\copilot.cmd'),
            (Join-Path $npmPrefix 'node_modules\.bin\copilot')
        )) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Install-WithWinget {
    param([Parameter(Mandatory = $true)][bool]$UsePrerelease)

    if (-not (Test-Command -Name winget)) {
        throw 'winget is not available in PATH.'
    }

    $packageId = if ($UsePrerelease) { 'GitHub.Copilot.Prerelease' } else { 'GitHub.Copilot' }
    Write-Host "Installing $packageId with winget"
    & winget install --id $packageId --exact --accept-source-agreements --accept-package-agreements --silent
}

function Install-WithNpm {
    param([Parameter(Mandatory = $true)][bool]$UsePrerelease)

    if (-not (Test-Command -Name npm)) {
        throw 'npm is not available in PATH.'
    }

    $packageName = if ($UsePrerelease) { '@github/copilot@prerelease' } else { '@github/copilot' }
    Write-Host "Installing $packageName with npm"
    & npm install -g $packageName
}

function Ensure-ProcessPath {
    $copilotPath = Resolve-CopilotCommand
    if (-not $copilotPath) {
        return $null
    }

    $copilotDir = Split-Path -Parent $copilotPath
    $currentPathEntries = $env:PATH -split ';' | Where-Object { $_ }
    if ($currentPathEntries -notcontains $copilotDir) {
        $env:PATH = "$copilotDir;$env:PATH"
    }

    return $copilotPath
}

$selectedMethod = $Method
if ($selectedMethod -eq 'auto') {
    if (Test-Command -Name winget) {
        $selectedMethod = 'winget'
    }
    elseif (Test-Command -Name npm) {
        $selectedMethod = 'npm'
    }
    else {
        throw 'Neither winget nor npm is available. Install one of them and re-run this script.'
    }
}

switch ($selectedMethod) {
    'winget' { Install-WithWinget -UsePrerelease:$Prerelease }
    'npm' { Install-WithNpm -UsePrerelease:$Prerelease }
    default { throw "Unsupported install method: $selectedMethod" }
}

$copilotCommand = Ensure-ProcessPath
if (-not $copilotCommand) {
    throw 'GitHub Copilot CLI installed, but the copilot command was not found in PATH. Open a new shell and run copilot --version.'
}

Write-Host "copilot command: $copilotCommand"

if (-not $SkipVersionCheck) {
    Write-Host 'Installed version:'
    & $copilotCommand --version
}

if (-not $SkipLoginReminder) {
    Write-Host ''
    Write-Host 'Next step:'
    Write-Host '  Run copilot and complete /login, or set GH_TOKEN/GITHUB_TOKEN with Copilot Requests permission.'
    Write-Host '  For unattended runs, make sure login succeeds before using the watcher script.'
}