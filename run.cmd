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

:: ── VirtualBox path for x64 VHD/VDI ──────────────────────────────────────────
if /I "%PLATFORM%"=="x64" (
    set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi"
    if exist "%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi" (
        echo [run.cmd] Launching VirtualBox with %ARTIFACT%...
        call :boot_virtualbox
        goto :eof
    ) else if exist "%~dp0artifacts\gentooha-x64-%FLAVOR%.vhd" (
        set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vhd"
        echo [run.cmd] Launching VirtualBox with %ARTIFACT%...
        call :boot_virtualbox
        goto :eof
    ) else (
        echo WARNING: No VirtualBox disk artifact found: %~dp0artifacts\gentooha-x64-%FLAVOR%.vdi or .vhd
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
if not defined ARTIFACT set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi"
if not exist "%ARTIFACT%" if exist "%~dp0artifacts\gentooha-x64-%FLAVOR%.vhd" set "ARTIFACT=%~dp0artifacts\gentooha-x64-%FLAVOR%.vhd"

echo     Checking VM registration...
"%VBOXMANAGE%" showvminfo "%VM%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo     Creating VM: %VM%
    "%VBOXMANAGE%" createvm --name "%VM%" --ostype Gentoo_64 --register
    "%VBOXMANAGE%" storagectl "%VM%" --name SATA --add sata --bootable on
)

echo     Ensuring VM is powered off for reconfiguration...
"%VBOXMANAGE%" controlvm "%VM%" poweroff >nul 2>&1
call :wait_vm_unlocked "%VM%"
call :clear_aborted_vm_state "%VM%"
call :wait_vm_unlocked "%VM%"

echo     Applying VM runtime settings...
set "RETRY_CMD=modifyvm "%VM%" --memory 4096 --cpus 2 --firmware bios --graphicscontroller vboxvga --accelerate3d off --nic1 nat"
call :run_vbox_retry "%VM%"
call :ensure_natpf_rule "%VM%" "ha-ui" "ha-ui,tcp,,8123,,8123"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to configure NAT forwarding rule ha-ui.
    pause
    exit /b 1
)
call :ensure_natpf_rule "%VM%" "ssh" "ssh,tcp,,2222,,22"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to configure NAT forwarding rule ssh.
    pause
    exit /b 1
)
set "RETRY_CMD=modifyvm "%VM%" --uart1 0x3F8 4 --uartmode1 file "%TEMP%\GentooHA-serial.log""
call :run_vbox_retry "%VM%"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to apply VM runtime settings.
    pause
    exit /b 1
)

echo     Cleaning stale VirtualBox disk registrations...
call :detach_known_vm_disks
"%VBOXMANAGE%" closemedium disk "%~dp0artifacts\gentooha-x64-%FLAVOR%.vdi" >nul 2>&1
"%VBOXMANAGE%" closemedium disk "%~dp0artifacts\gentooha-x64-%FLAVOR%.vhd" >nul 2>&1
"%VBOXMANAGE%" closemedium disk "%ARTIFACT%" >nul 2>&1

echo     Attaching disk: %ARTIFACT%
set "RETRY_CMD=storageattach "%VM%" --storagectl SATA --port 0 --device 0 --type hdd --medium "%ARTIFACT%""
call :run_vbox_retry "%VM%"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to attach disk image. Run build.cmd to regenerate artifact.
    pause
    exit /b 1
)

echo     Starting VM...
set "RETRY_CMD=startvm "%VM%" --type gui"
call :run_vbox_retry "%VM%"
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
echo  Serial boot log:   %TEMP%\GentooHA-serial.log
echo ============================================================
echo.
pause
exit /b 0

:wait_vm_unlocked
setlocal EnableDelayedExpansion
set "WAIT_VM=%~1"
set /a WAIT_COUNT=0
:wait_vm_unlocked_loop
set /a WAIT_COUNT+=1
if !WAIT_COUNT! GTR 60 goto :wait_vm_unlocked_done
"%VBOXMANAGE%" showvminfo "%WAIT_VM%" --machinereadable | findstr /I /C:"SessionState=\"unlocked\"" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
    timeout /t 1 /nobreak >nul
    goto :wait_vm_unlocked_loop
)
:wait_vm_unlocked_done
endlocal & exit /b 0

:clear_aborted_vm_state
setlocal
set "CHECK_VM=%~1"
"%VBOXMANAGE%" showvminfo "%CHECK_VM%" --machinereadable | findstr /C:"VMState=\"aborted\"" >nul 2>&1
if %ERRORLEVEL% NEQ 0 endlocal & exit /b 0
echo     Clearing aborted VM state...
set "RETRY_CMD=discardstate "%CHECK_VM%""
call :run_vbox_retry "%CHECK_VM%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

:ensure_natpf_rule
setlocal
set "RULE_VM=%~1"
set "RULE_NAME=%~2"
set "RULE_SPEC=%~3"
"%VBOXMANAGE%" showvminfo "%RULE_VM%" --machinereadable | findstr /C:"Forwarding(0)=\"%RULE_SPEC%\"" /C:"Forwarding(1)=\"%RULE_SPEC%\"" >nul 2>&1
if %ERRORLEVEL% EQU 0 endlocal & exit /b 0
call :wait_vm_unlocked "%RULE_VM%"
"%VBOXMANAGE%" modifyvm "%RULE_VM%" --natpf1 delete "%RULE_NAME%" >nul 2>&1
set "RETRY_CMD=modifyvm "%RULE_VM%" --natpf1 "%RULE_SPEC%""
call :run_vbox_retry "%RULE_VM%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

:run_vbox_retry
setlocal EnableDelayedExpansion
set "RETRY_VM=%~1"
set /a RETRY_COUNT=0
:run_vbox_retry_loop
set /a RETRY_COUNT+=1
"%VBOXMANAGE%" !RETRY_CMD!
set "RC=!ERRORLEVEL!"
if !RC! EQU 0 endlocal & exit /b 0
if !RETRY_COUNT! GEQ 15 endlocal & exit /b !RC!
call :wait_vm_unlocked "%RETRY_VM%"
timeout /t 1 /nobreak >nul
goto :run_vbox_retry_loop

:detach_known_vm_disks
for %%V in (GentooHA GentooHA-1 GentooHA-Test) do (
    "%VBOXMANAGE%" showvminfo "%%V" >nul 2>&1
    if not errorlevel 1 (
        "%VBOXMANAGE%" controlvm "%%V" poweroff >nul 2>&1
        "%VBOXMANAGE%" storageattach "%%V" --storagectl SATA --port 0 --device 0 --medium none >nul 2>&1
        "%VBOXMANAGE%" storageattach "%%V" --storagectl SATA --port 1 --device 0 --medium none >nul 2>&1
        "%VBOXMANAGE%" storageattach "%%V" --storagectl SATA --port 2 --device 0 --medium none >nul 2>&1
        "%VBOXMANAGE%" storageattach "%%V" --storagectl SATA --port 3 --device 0 --medium none >nul 2>&1
    )
)
exit /b 0
