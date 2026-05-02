@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "STATE_DIR=%SCRIPT_DIR%.state"
set "STATE_FILE=%STATE_DIR%\wsl_debian_bootstrap.done"

if not exist "%STATE_DIR%" mkdir "%STATE_DIR%"

if exist "%STATE_FILE%" (
  echo [INFO] Completion marker already exists: %STATE_FILE%
  choice /C YN /M "Run bootstrap again anyway?"
  if errorlevel 2 (
    echo [INFO] Skipping because completion marker is present.
    exit /b 0
  )
)

echo [INFO] WSL prerequisite script
echo [INFO] This script WILL delete an existing Debian WSL distro without backup.
echo.

where wsl >nul 2>nul
if errorlevel 1 (
  echo [ERROR] WSL is not available on this system.
  exit /b 1
)

for /f "tokens=*" %%D in ('wsl --list --quiet ^| findstr /R /I "^Debian"') do (
  set "EXISTING_DISTRO=%%D"
  goto :foundDistro
)

set "EXISTING_DISTRO="
:foundDistro

if defined EXISTING_DISTRO (
  echo [WARN] Found existing Debian distro: !EXISTING_DISTRO!
  choice /C YN /M "Delete this distro now?"
  if errorlevel 2 (
    echo [INFO] Aborted by user.
    exit /b 0
  )

  echo [INFO] Unregistering distro !EXISTING_DISTRO! ...
  wsl --unregister "!EXISTING_DISTRO!"
  if errorlevel 1 (
    echo [ERROR] Failed to unregister distro !EXISTING_DISTRO!.
    exit /b 1
  )
) else (
  echo [INFO] No existing Debian distro found.
)

echo [INFO] Installing Debian from WSL online catalog...
wsl --install -d Debian
if errorlevel 1 (
  echo [ERROR] Failed to install Debian. Check output from wsl --install.
  exit /b 1
)

echo [INFO] Setting Debian to WSL2...
wsl --set-version Debian 2
if errorlevel 1 (
  echo [WARN] Could not set version to WSL2 automatically.
)

echo [INFO] Running first-boot bootstrap as root...
wsl -d Debian -u root -- bash -lc "set -euo pipefail; apt update; DEBIAN_FRONTEND=noninteractive apt -y full-upgrade; DEBIAN_FRONTEND=noninteractive apt -y install build-essential git curl jq wget ca-certificates gnupg lsb-release debootstrap"
if errorlevel 1 (
  echo [ERROR] Bootstrap package install failed.
  exit /b 1
)

echo [INFO] Marking completion in %STATE_FILE%
>"%STATE_FILE%" echo completed=%DATE% %TIME%

echo [INFO] Prerequisite completed successfully.
exit /b 0
