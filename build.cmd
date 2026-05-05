@echo off
:: build.cmd — Windows-only launcher (CMD / PowerShell on Windows).
:: This file uses the WSL2 path exclusively.  On Linux, use build.sh directly.
setlocal EnableExtensions DisableDelayedExpansion

:: Verify WSL2 is available
where wsl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo ERROR: WSL2 is not installed or not in PATH.
  echo        Install WSL2 first, then run scripts\windows\prereq_wsl_debian.cmd
  pause
  exit /b 1
)
echo [build.cmd] Windows environment detected - using WSL2 build path.

echo ============================================================
echo  GentooHA Build Launcher
echo ============================================================
echo.
echo Platforms:
echo   x64      - Generic PC / VM  (produces preinstalled .img + .vdi)
echo   pi3      - Raspberry Pi 3   (produces .img)
echo   pi4      - Raspberry Pi 4   (produces .img)
echo   pizero2  - Raspberry Pi Zero 2 W  (produces .img)
echo   bbb      - BeagleBone Black  (produces .img)
echo   pbv2     - PocketBeagle v2 with GPU  (produces .img)
echo.

:ask_platform
set "PLATFORM="
set /P PLATFORM="Platform [x64]: "
if "%PLATFORM%"=="" set "PLATFORM=x64"
if /I "%PLATFORM%"=="x64"     goto platform_ok
if /I "%PLATFORM%"=="pi3"     goto platform_ok
if /I "%PLATFORM%"=="pi4"     goto platform_ok
if /I "%PLATFORM%"=="pizero2" goto platform_ok
if /I "%PLATFORM%"=="bbb"     goto platform_ok
if /I "%PLATFORM%"=="pbv2"    goto platform_ok
echo Invalid platform. Choose: x64  pi3  pi4  pizero2  bbb  pbv2
goto ask_platform

:platform_ok
echo.
echo Flavors:
echo   live       - Bootable live system
echo   installer  - Installs to disk on first boot
echo   debug      - Verbose boot diagnostics on console
echo.

:ask_flavor
set "FLAVOR="
set /P FLAVOR="Flavor [installer]: "
if "%FLAVOR%"=="" set "FLAVOR=installer"
if /I "%FLAVOR%"=="live"      goto flavor_ok
if /I "%FLAVOR%"=="installer" goto flavor_ok
if /I "%FLAVOR%"=="debug"     goto flavor_ok
echo Invalid flavor. Choose: live  installer  debug
goto ask_flavor

:flavor_ok
echo.

:ask_stage
set "START_STAGE="
set /P START_STAGE="Start from stage (1-12) [1]: "
if "%START_STAGE%"=="" set "START_STAGE=1"
if "%START_STAGE%"=="1"  goto stage_ok
if "%START_STAGE%"=="2"  goto stage_ok
if "%START_STAGE%"=="3"  goto stage_ok
if "%START_STAGE%"=="4"  goto stage_ok
if "%START_STAGE%"=="5"  goto stage_ok
if "%START_STAGE%"=="6"  goto stage_ok
if "%START_STAGE%"=="7"  goto stage_ok
if "%START_STAGE%"=="8"  goto stage_ok
if "%START_STAGE%"=="9"  goto stage_ok
if "%START_STAGE%"=="10" goto stage_ok
if "%START_STAGE%"=="11" goto stage_ok
if "%START_STAGE%"=="12" goto stage_ok
echo Enter a number from 1 to 12.
goto ask_stage

:stage_ok
echo.

:ask_clean
set "CLEAN_ANS=N"
set /P CLEAN_ANS="Clean prior stage state? (y/N) [N]: "
set "CLEAN_STATE=false"
if /I "%CLEAN_ANS%"=="y" set "CLEAN_STATE=true"

:ask_artifacts
set "ARTIFACT_ACTION=A"
set /P ARTIFACT_ACTION="Handle existing artifacts? archive/remove/keep (a/y/n) [a]: "
if "%ARTIFACT_ACTION%"=="" set "ARTIFACT_ACTION=A"
if /I "%ARTIFACT_ACTION%"=="a" goto artifacts_ok
if /I "%ARTIFACT_ACTION%"=="y" goto artifacts_ok
if /I "%ARTIFACT_ACTION%"=="n" goto artifacts_ok
echo Invalid choice. Use: a (archive), y (remove), n (keep)
goto ask_artifacts

:artifacts_ok

:: Auto-resume: read completed_stage from WSL state directory
set "COMPLETED_STAGE=0"
for /f "delims=" %%S in ('wsl -d Debian -u root -- bash -c "cat /var/lib/ha-gentoo-hybrid/state/completed_stage 2>/dev/null || echo 0" 2^>nul') do set "COMPLETED_STAGE=%%S"
if "%COMPLETED_STAGE%"=="12" (
  echo.
  echo [build.cmd] All 12 stages already completed. Nothing to do.
  echo             Run reset.cmd to clear stage tracking and rebuild from scratch.
  pause
  exit /b 0
)
:: Advance START_STAGE if it is at or below the already-completed stage
set /a AUTO_START=%COMPLETED_STAGE%+1
if %COMPLETED_STAGE% GTR 0 (
  if %START_STAGE% LEQ %COMPLETED_STAGE% (
    echo [build.cmd] Resuming from stage %AUTO_START% ^(completed_stage=%COMPLETED_STAGE%^).
    set "START_STAGE=%AUTO_START%"
  )
)

echo.
echo ============================================================
echo  Build summary
echo    PLATFORM    = %PLATFORM%
echo    FLAVOR      = %FLAVOR%
echo    START_STAGE = %START_STAGE%
echo    CLEAN_STATE = %CLEAN_STATE%
echo    ARTIFACTS   = %ARTIFACT_ACTION% (a=archive, y=remove, n=keep)
echo ============================================================
echo.

:ask_proceed
set "PROCEED=Y"
set /P PROCEED="Proceed? (Y/n) [Y]: "
if /I "%PROCEED%"=="n" ( echo Aborted. & pause & exit /b 0 )

:: Determine WSL distro to use for building
set "WSL_DISTRO="
wsl -d GentooHA -- echo ok >nul 2>&1 && set "WSL_DISTRO=GentooHA"
if "%WSL_DISTRO%"=="" (
  wsl -d Debian -- echo ok >nul 2>&1 && set "WSL_DISTRO=Debian"
)
if "%WSL_DISTRO%"=="" (
  echo ERROR: No suitable WSL distro found. Need GentooHA or Debian.
  pause
  exit /b 1
)
echo Using WSL distro: %WSL_DISTRO%
echo.

:: Run build.sh inside WSL
set "WIN_PATH=%~dp0"
set "WSL_PATH="
for /f "delims=" %%P in ('wsl -d %WSL_DISTRO% -- wslpath "%WIN_PATH%" 2^>nul') do set "WSL_PATH=%%P"
if "%WSL_PATH%"=="" (
  rem Fallback conversion via PowerShell: C:\foo\bar\ -> /mnt/c/foo/bar
  set "WIN_PATH_ENV=%WIN_PATH%"
  for /f "delims=" %%P in ('powershell -NoProfile -Command "$p=$env:WIN_PATH_ENV; if ([string]::IsNullOrWhiteSpace($p)) { exit 1 }; $p=$p.TrimEnd('\\'); $d=$p.Substring(0,1).ToLower(); $r=$p.Substring(2).Replace('\\','/'); '/mnt/' + $d + $r" 2^>nul') do set "WSL_PATH=%%P"
)
rem Normalize any accidental backslashes from wslpath/fallback output
set "WSL_PATH=%WSL_PATH:\=/%"
if "%WSL_PATH%"=="" (
  echo ERROR: Unable to translate Windows path to WSL path.
  pause
  exit /b 1
)
:: Strip trailing slash
if "%WSL_PATH:~-1%"=="/" set "WSL_PATH=%WSL_PATH:~0,-1%"

wsl -d %WSL_DISTRO% -- bash -c "export PLATFORM=%PLATFORM% FLAVOR=%FLAVOR% START_STAGE=%START_STAGE% CLEAN_STATE=%CLEAN_STATE% ARTIFACT_ACTION=%ARTIFACT_ACTION%; cd '%WSL_PATH%'; bash build.sh --non-interactive"
if %ERRORLEVEL% NEQ 0 (
  echo.
  echo ERROR: Build failed. See output above.
  pause
  exit /b 1
)

:: For x64 builds on Windows, optionally run the import/boot step
if /I "%PLATFORM%"=="x64" (
  echo.
  set "RUN_IMPORT=Y"
  set /P RUN_IMPORT="Import and boot GentooHA in WSL2 now? (Y/n) [Y]: "
  if /I not "%RUN_IMPORT%"=="n" (
    call "%~dp0scripts\temp\ai\import_and_boot_gentooha.cmd" 1
  )
)

echo.
echo Build complete.
echo Artifacts: gentooha-%PLATFORM%-%FLAVOR%.img and gentooha-%PLATFORM%-%FLAVOR%.vdi
echo Location: %WIN_PATH%artifacts\ and /var/lib/ha-gentoo-hybrid/artifacts/ inside WSL
echo.
pause
