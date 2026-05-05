@echo off
:: run.cmd — Boot and validate a GentooHA artifact produced by build.cmd
:: Usage: run.cmd [platform] [flavor] [start_step]
:: Windows environment detected — uses WSL2 import+boot or VirtualBox
setlocal

set "PLATFORM=%~1"
set "FLAVOR=%~2"
set "START_STEP=%~3"
set "DISTRO_NAME=GentooHA"
set "WSL_INSTALL_DIR=C:\Users\tamus\AppData\Local\GentooHA"

if "%PLATFORM%"=="" set "PLATFORM=x64"
if "%FLAVOR%"==""   set "FLAVOR=debug"
if "%START_STEP%"=="" set "START_STEP=1"

echo [run.cmd] Windows environment detected.

:: ── VirtualBox path for x64 VDI ──────────────────────────────────────────────
if /I "%PLATFORM%"=="x64" (
    set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi"
    if exist "%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi" (
        echo [run.cmd] Launching VirtualBox with %ARTIFACT%...
        call :boot_virtualbox
        goto :eof
    ) else (
        echo WARNING: VDI not found: %~dp0artifacts\gentooha-x64-%FLAVOR%.vdi
        echo          Run build.cmd first to produce the artifact.
        echo          Falling back to WSL2 import path...
    )
)

:: ── Delegate remaining steps to WSL2 via run.sh ──────────────────────────────
where wsl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: WSL2 not found. Install WSL2 and retry.
    pause
    exit /b 1
)

wsl -d Debian -u root -- bash -lc "cd /mnt/c/Users/tamus/projects/linux/home_assistant_1 && PLATFORM=%PLATFORM% FLAVOR=%FLAVOR% START_STEP=%START_STEP% bash run.sh"
exit /b %ERRORLEVEL%

:: ── VirtualBox boot subroutine ───────────────────────────────────────────────
:boot_virtualbox
set "VBOXMANAGE=C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
if not exist "%VBOXMANAGE%" (
    echo ERROR: VBoxManage.exe not found at expected path.
    echo        Install VirtualBox or update VBOXMANAGE path in run.cmd
    pause
    exit /b 1
)

set "VM=%DISTRO_NAME%"
set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi"

echo     Checking VM registration...
"%VBOXMANAGE%" showvminfo "%VM%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo     Creating VM: %VM%
    "%VBOXMANAGE%" createvm --name "%VM%" --ostype Gentoo_64 --register
    "%VBOXMANAGE%" modifyvm "%VM%" --memory 4096 --cpus 2 --firmware bios ^
        --graphicscontroller vboxvga --accelerate3d off ^
        --nic1 nat ^
        --natpf1 "ha-ui,tcp,,8123,,8123" ^
        --natpf1 "ssh,tcp,,2222,,22"
    "%VBOXMANAGE%" storagectl "%VM%" --name SATA --add sata --bootable on
)

echo     Attaching disk: %ARTIFACT%
"%VBOXMANAGE%" closemedium disk "%ARTIFACT%" >nul 2>&1
"%VBOXMANAGE%" storageattach "%VM%" --storagectl SATA --port 0 --device 0 ^
    --type hdd --medium "%ARTIFACT%"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to attach VDI. Run build.cmd to regenerate artifact.
    pause
    exit /b 1
)

echo     Starting VM...
"%VBOXMANAGE%" startvm "%VM%" --type gui
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to start VM.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  GentooHA VM is starting in VirtualBox.
echo  Home Assistant UI: http://localhost:8123
echo    (available after Supervisor finishes pulling its image)
echo  SSH into guest:    ssh -p 2222 root@127.0.0.1
echo ============================================================
echo.
pause
exit /b 0
