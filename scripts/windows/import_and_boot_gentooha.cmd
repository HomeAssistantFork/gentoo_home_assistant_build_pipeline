@echo off
setlocal

set "START_STEP=%~1"
set "GENTOO_USER=%~2"
set "WSL_USER_SWITCH="
set "EFFECTIVE_USER="
if "%START_STEP%"=="" set "START_STEP=1"

echo %START_STEP%| findstr /r "^[1-6]$" >nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Invalid step "%START_STEP%". Use 1-6.
    echo Usage: %~nx0 [start_step] [gentoo_user]
    pause
    exit /b 1
)

if not "%GENTOO_USER%"=="" (
    set "EFFECTIVE_USER=%GENTOO_USER%"
    set "WSL_USER_SWITCH=-u %GENTOO_USER%"
)

if "%GENTOO_USER%"=="" (
    if "%START_STEP%"=="4" call :resolve_wsl_user
    if "%START_STEP%"=="5" call :resolve_wsl_user
    if "%START_STEP%"=="6" call :resolve_wsl_user
)

echo ============================================================
echo  GentooHA WSL2 Import and Boot Validation
echo ============================================================
echo  Starting from step: %START_STEP%
if "%EFFECTIVE_USER%"=="" (
    echo  Privileged user: default distro user ^(sudo if needed^)
) else (
    if /I "%EFFECTIVE_USER%"=="root" (
        echo  Privileged user: root ^(direct^)
    ) else (
        echo  Privileged user: %EFFECTIVE_USER% ^(sudo if needed^)
    )
)
echo.

if "%START_STEP%"=="1" goto step1
if "%START_STEP%"=="2" goto step2
if "%START_STEP%"=="3" goto step3
if "%START_STEP%"=="4" goto step4
if "%START_STEP%"=="5" goto step5
if "%START_STEP%"=="6" goto step6

echo ERROR: Invalid step "%START_STEP%".
pause
goto :eof

:resolve_wsl_user
for /f "usebackq delims=" %%U in (`wsl -d GentooHA -- bash -lc "id -un 2>/dev/null || true"`) do (
    if not "%%U"=="" set "EFFECTIVE_USER=%%U"
)

if "%EFFECTIVE_USER%"=="" set "EFFECTIVE_USER=root"

if /I "%EFFECTIVE_USER%"=="root" (
    for /f "usebackq delims=" %%U in (`wsl -d GentooHA -- bash -lc "getent passwd | awk -F: '$3>=1000 && $3<60000 && $1!=\"nobody\" {print $1; exit}' 2>/dev/null || true"`) do (
        if not "%%U"=="" set "EFFECTIVE_USER=%%U"
    )
)

if not "%EFFECTIVE_USER%"=="" set "WSL_USER_SWITCH=-u %EFFECTIVE_USER%"
exit /b 0
exit /b 1

:: --- Step 1: Export Gentoo tarball inside Debian (synchronous + verbose) ---
:step1
echo [1/6] Exporting Gentoo tarball inside Debian (synchronous, verbose)...
wsl -d Debian -u root -- bash -c "set -e; mkdir -p /var/lib/ha-gentoo-hybrid/downloads; rm -f /var/lib/ha-gentoo-hybrid/downloads/gentoo-ha-fixed.tar.gz; tar --numeric-owner -cvzf /var/lib/ha-gentoo-hybrid/downloads/gentoo-ha-fixed.tar.gz -C /mnt/gentoo --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run --exclude=./tmp ."
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Tarball export failed.
    pause
    exit /b 1
)
echo     Export complete. Verifying tarball...
wsl -d Debian -u root -- bash -c "ls -lh /var/lib/ha-gentoo-hybrid/downloads/gentoo-ha-fixed.tar.gz"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Tarball not found after export.
    pause
    exit /b 1
)
echo.

:: --- Step 2: Copy tarball to Windows filesystem (wsl --import requires a Windows path) ---
:step2
echo [2/6] Copying tarball to Windows temp folder for import...
echo     (This may take a few minutes for a ~1.8 GB file)
copy "\\wsl$\Debian\var\lib\ha-gentoo-hybrid\downloads\gentoo-ha-fixed.tar.gz" "%TEMP%\gentoo-ha-fixed.tar.gz"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Could not copy tarball to %TEMP%. Check WSL is running.
    pause
    exit /b 1
)
echo     Copy done.
echo.

:: --- Step 3: Unregister old GentooHA if it exists, then import fresh ---
:step3
echo [3/6] Importing GentooHA WSL2 distro...
wsl --unregister GentooHA 2>nul
echo     (Ignore error above if GentooHA did not exist)
if not exist "C:\Users\tamus\AppData\Local\GentooHA" mkdir "C:\Users\tamus\AppData\Local\GentooHA"
wsl --import GentooHA "C:\Users\tamus\AppData\Local\GentooHA" "%TEMP%\gentoo-ha-fixed.tar.gz" --version 2
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: WSL import failed.
    pause
    exit /b 1
)
echo     Import successful. Cleaning up temp file...
del /f "%TEMP%\gentoo-ha-fixed.tar.gz" >nul 2>&1
echo.

:: --- Step 4: Ensure /etc/wsl.conf has systemd=true, restart WSL if changed ---
:step4
echo [4/6] Checking WSL configuration (systemd + automount)...
wsl -d GentooHA -- bash -c "grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null && echo WSL_CONF_OK || echo WSL_CONF_MISSING" > "%TEMP%\wslconf_check.txt" 2>&1
set "WSL_CONF_RESULT="
for /f "usebackq delims=" %%L in ("%TEMP%\wslconf_check.txt") do set "WSL_CONF_RESULT=%%L"
del /f "%TEMP%\wslconf_check.txt" >nul 2>&1
if "%WSL_CONF_RESULT%"=="WSL_CONF_OK" (
    echo     /etc/wsl.conf already has systemd=true. No changes needed.
) else (
    echo     Writing /etc/wsl.conf with systemd=true and restarting WSL...
    wsl -d GentooHA -- bash -c "printf '[boot]\nsystemd=true\n\n[automount]\nenabled=true\noptions=metadata\n\n[interop]\nenabled=true\n' > /etc/wsl.conf && echo WSL_CONF_WRITTEN"
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Failed to write /etc/wsl.conf
        pause
        exit /b 1
    )
    echo     Shutting down WSL to apply systemd change...
    wsl --shutdown
    echo     Waiting 8 seconds for WSL to fully stop and restart...
    ping -n 9 127.0.0.1 >nul
    echo     Verifying GentooHA boots with systemd=true...
    wsl -d GentooHA -- bash -c "ps -p 1 -o comm= 2>/dev/null || echo PID1_UNKNOWN" > "%TEMP%\pid1_check.txt" 2>&1
    set "PID1_NAME="
    for /f "usebackq delims=" %%L in ("%TEMP%\pid1_check.txt") do set "PID1_NAME=%%L"
    del /f "%TEMP%\pid1_check.txt" >nul 2>&1
    echo     PID1=%PID1_NAME%
    if not "%PID1_NAME%"=="systemd" (
        echo WARNING: PID 1 is not systemd after restart. Docker may still fail.
        echo          Check /etc/wsl.conf inside GentooHA and ensure WSL version is 2.
    ) else (
        echo     systemd is running as PID 1. WSL restart successful.
    )
)
echo.

:: --- Step 5: Fix iptables mode (required for Docker in WSL2) ---
:step5
echo [5/6] Configuring GentooHA (iptables legacy mode for Docker)...
wsl -d GentooHA %WSL_USER_SWITCH% -- bash -c "set -e; if command -v update-alternatives >/dev/null 2>&1; then update-alternatives --set iptables /usr/sbin/iptables-legacy; update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy; echo IPTABLES=legacy-via-update-alternatives; exit 0; fi; if command -v iptables-legacy >/dev/null 2>&1 && command -v ip6tables-legacy >/dev/null 2>&1; then echo 'INFO: update-alternatives not found; legacy binaries are present.'; echo IPTABLES=legacy-binaries-present; exit 0; fi; echo 'ERROR: Unable to configure legacy iptables (missing update-alternatives and legacy binaries).'; exit 50"
if %ERRORLEVEL% NEQ 0 (
    if /I "%EFFECTIVE_USER%"=="root" (
        echo ERROR: Step 5 failed while configuring iptables as root.
        pause
        exit /b 1
    ) else (
        echo INFO: Retrying Step 5 with sudo authentication...
        wsl -d GentooHA %WSL_USER_SWITCH% -- bash -lc "sudo -k; sudo -v; sudo bash -lc 'set -e; if command -v update-alternatives >/dev/null 2>&1; then update-alternatives --set iptables /usr/sbin/iptables-legacy; update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy; echo IPTABLES=legacy-via-update-alternatives; exit 0; fi; if command -v iptables-legacy >/dev/null 2>&1 && command -v ip6tables-legacy >/dev/null 2>&1; then echo '"'"'INFO: update-alternatives not found; legacy binaries are present.'"'"'; echo IPTABLES=legacy-binaries-present; exit 0; fi; echo '"'"'ERROR: Unable to configure legacy iptables (missing update-alternatives and legacy binaries).'"'"'; exit 50'"
        if %ERRORLEVEL% NEQ 0 (
            echo ERROR: Step 5 failed while configuring iptables.
            pause
            exit /b 1
        )
    )
)
echo.

:: --- Step 6: Start Docker and validate services ---
:step6
echo [6/6] Starting Docker and validating services...

echo     Checking systemd state...
set "SYSTEMD_STATE="
for /f "usebackq delims=" %%S in (`wsl -d GentooHA -- systemctl is-system-running 2^>nul`) do set "SYSTEMD_STATE=%%S"
if "%SYSTEMD_STATE%"=="" set "SYSTEMD_STATE=unknown"
echo     systemd state: %SYSTEMD_STATE%

if /I "%SYSTEMD_STATE%"=="initializing" (
    echo     systemd is still initializing. Showing pending jobs:
    wsl -d GentooHA -- systemctl list-jobs --no-pager
    echo     Attempting one-time firstboot unblock if needed...
    wsl -d GentooHA -- bash -c "systemd-machine-id-setup || true; if command -v dbus-uuidgen >/dev/null 2>&1; then dbus-uuidgen --ensure=/etc/machine-id || true; fi; [ -e /var/lib/dbus/machine-id ] || ln -sf /etc/machine-id /var/lib/dbus/machine-id; systemctl disable --now systemd-firstboot.service >/dev/null 2>&1 || true; systemctl mask systemd-firstboot.service >/dev/null 2>&1 || true"
    wsl -d GentooHA -- systemctl start dbus
    wsl -d GentooHA -- systemctl start systemd-logind
    echo     Re-checking systemd state...
    set "SYSTEMD_STATE="
    for /f "usebackq delims=" %%S in (`wsl -d GentooHA -- systemctl is-system-running 2^>nul`) do set "SYSTEMD_STATE=%%S"
    if "%SYSTEMD_STATE%"=="" set "SYSTEMD_STATE=unknown"
    echo     systemd state after unblock: %SYSTEMD_STATE%
)

echo     Starting Docker...
wsl -d GentooHA -- systemctl start docker
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Docker failed to start. Journal output:
    wsl -d GentooHA -- journalctl -u docker -n 80 --no-pager
    pause
    exit /b 1
)
echo --- docker status ---
wsl -d GentooHA -- systemctl status docker --no-pager -l
echo.
echo --- os-agent status ---
wsl -d GentooHA -- systemctl start os-agent
wsl -d GentooHA -- systemctl status os-agent --no-pager -l
echo.
echo --- hassio-supervisor status ---
wsl -d GentooHA -- systemctl start hassio-supervisor
wsl -d GentooHA -- systemctl status hassio-supervisor --no-pager -l
echo.
echo --- IPv4 forwarding note ---
wsl -d GentooHA -- sysctl -w net.ipv4.ip_forward=1
echo.

echo ============================================================
echo  GentooHA is imported and running.
echo  Enter the distro:   wsl -d GentooHA
echo  Watch HA startup:   wsl -d GentooHA -- journalctl -fu hassio-supervisor
echo  Home Assistant UI:  http://localhost:8123
echo    (available after Supervisor finishes pulling its image)
echo ============================================================
echo.
pause
