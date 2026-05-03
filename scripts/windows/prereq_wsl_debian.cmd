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
echo [INFO] This script sets up a Debian WSL distro for building GentooHA.
echo [INFO] An existing Debian distro will NOT be removed.
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
  echo [INFO] Debian distro already present: !EXISTING_DISTRO!
  echo [INFO] Skipping re-install to preserve existing environment.
  echo [INFO] Running bootstrap packages inside existing distro instead...
  set "BOOTSTRAP_CMD=set -euo pipefail; apt update; DEBIAN_FRONTEND=noninteractive apt -y full-upgrade; DEBIAN_FRONTEND=noninteractive apt -y install build-essential git curl jq wget ca-certificates gnupg lsb-release debootstrap"
  wsl -d "!EXISTING_DISTRO!" -u root -- bash -lc "!BOOTSTRAP_CMD!"
  if errorlevel 1 (
    echo [ERROR] Bootstrap package update failed inside !EXISTING_DISTRO!.
    exit /b 1
  )
  goto :bootstrap_done
)

echo [INFO] No existing Debian distro found. Installing from WSL online catalog...
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

:bootstrap_done
echo [INFO] Marking completion in %STATE_FILE%
>"%STATE_FILE%" echo completed=%DATE% %TIME%

echo [INFO] Prerequisite completed successfully.
exit /b 0
