@echo off
:: reset.cmd — Clear GentooHA stage-tracking state so the next build.cmd run
::             starts from stage 1.  Does NOT delete rootfs or artifact files.
setlocal EnableExtensions DisableDelayedExpansion

echo [reset] Clearing stage tracking state...

:: Try Debian WSL first, then fall back to default WSL distro
wsl -d Debian -u root -- bash -c "rm -f /var/lib/ha-gentoo-hybrid/state/stage*.done /var/lib/ha-gentoo-hybrid/state/completed_stage 2>/dev/null; echo RESET_DONE" 2>nul | findstr /C:"RESET_DONE" >nul
if %ERRORLEVEL% EQU 0 goto :reset_ok

wsl -u root -- bash -c "rm -f /var/lib/ha-gentoo-hybrid/state/stage*.done /var/lib/ha-gentoo-hybrid/state/completed_stage 2>/dev/null; echo RESET_DONE" 2>nul | findstr /C:"RESET_DONE" >nul
if %ERRORLEVEL% EQU 0 goto :reset_ok

echo [reset] WARNING: Could not clear state via WSL. Is WSL2 running?
exit /b 1

:reset_ok
echo [reset] Stage tracking cleared.
echo [reset] Next build.cmd run will start from stage 1.
endlocal
