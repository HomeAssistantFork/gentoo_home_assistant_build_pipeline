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

:: ── Load persisted config + completed_stage from WSL ─────────────────────
set "SAVED_PLATFORM="
set "SAVED_FLAVOR="
set "SAVED_USE_BINPKG="
set "SAVED_X64_ARTIFACT_FORMAT="
set "SAVED_BUILD_UML_KERNEL="
set "COMPLETED_STAGE=0"

for /f "delims=" %%L in ('wsl -d Debian -u root -- bash -c "source /var/lib/ha-gentoo-hybrid/state/build_config 2>/dev/null; echo SAVED_PLATFORM=${SAVED_PLATFORM:-}; echo SAVED_FLAVOR=${SAVED_FLAVOR:-}; echo SAVED_USE_BINPKG=${SAVED_USE_BINPKG:-}; echo SAVED_X64_ARTIFACT_FORMAT=${SAVED_X64_ARTIFACT_FORMAT:-}; echo SAVED_BUILD_UML_KERNEL=${SAVED_BUILD_UML_KERNEL:-}" 2^>nul') do (
  set "%%L"
)
for /f "delims=" %%S in ('wsl -d Debian -u root -- bash -c "cat /var/lib/ha-gentoo-hybrid/state/completed_stage 2>/dev/null || echo 0" 2^>nul') do set "COMPLETED_STAGE=%%S"

:: Compute default start stage from completed_stage
set /a DEFAULT_STAGE=%COMPLETED_STAGE%+1
if %DEFAULT_STAGE% GTR 13 set "DEFAULT_STAGE=13"
if %DEFAULT_STAGE% LSS 1  set "DEFAULT_STAGE=1"

:: Apply saved defaults (may be empty, prompts will fall back to hardcoded)
if not "%SAVED_PLATFORM%"=="" set "DEF_PLATFORM=%SAVED_PLATFORM%"
if "%DEF_PLATFORM%"=="" set "DEF_PLATFORM=x64"

if not "%SAVED_FLAVOR%"=="" set "DEF_FLAVOR=%SAVED_FLAVOR%"
if "%DEF_FLAVOR%"=="" set "DEF_FLAVOR=live"
if /I "%DEF_FLAVOR%"=="installer" set "DEF_FLAVOR=live"

set "DEF_BINPKG=b"
if /I "%SAVED_USE_BINPKG%"=="false" set "DEF_BINPKG=s"

if "%COMPLETED_STAGE%"=="13" (
  echo.
  echo [build.cmd] All 13 stages already completed. Nothing to do.
  echo             Run reset.cmd to clear stage tracking and rebuild from scratch.
  pause
  exit /b 0
)

echo ============================================================
echo  GentooHA Build Launcher (13-Stage Portage-Based Build)
echo ============================================================
echo.
echo Platforms:
echo   x64      - Generic PC / VM  (supports .vhd, .vdi, .iso, .img)
echo   pi3      - Raspberry Pi 3   (produces .img)
echo   pi4      - Raspberry Pi 4   (produces .img)
echo   pizero2  - Raspberry Pi Zero 2 W  (produces .img)
echo   bbb      - BeagleBone Black  (produces .img)
echo   pbv2     - PocketBeagle v2 with GPU  (produces .img)
echo.

:ask_platform
set "PLATFORM="
set /P PLATFORM="Platform [%DEF_PLATFORM%]: "
if "%PLATFORM%"=="" set "PLATFORM=%DEF_PLATFORM%"
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
echo   live       - Unified release image ^(replaces prior live + installer split^)
echo   debug      - Verbose boot diagnostics on console; BIOS-oriented disk boot
echo   installer  - Compatibility alias for live
echo.

:ask_flavor
set "FLAVOR="
set /P FLAVOR="Flavor [%DEF_FLAVOR%]: "
if "%FLAVOR%"=="" set "FLAVOR=%DEF_FLAVOR%"
if /I "%FLAVOR%"=="live"      goto flavor_ok
if /I "%FLAVOR%"=="installer" goto flavor_ok
if /I "%FLAVOR%"=="debug"     goto flavor_ok
echo Invalid flavor. Choose: live  installer  debug
goto ask_flavor

:flavor_ok
if /I "%FLAVOR%"=="installer" set "FLAVOR=live"
if /I "%PLATFORM%"=="x64" (
  echo.
  if /I "%FLAVOR%"=="debug" (
    if "%SAVED_X64_ARTIFACT_FORMAT%"=="" set "SAVED_X64_ARTIFACT_FORMAT=vdi img"
  ) else (
    if "%SAVED_X64_ARTIFACT_FORMAT%"=="" set "SAVED_X64_ARTIFACT_FORMAT=iso img"
  )
  set "X64_ARTIFACT_FORMATS="
  set /P X64_ARTIFACT_FORMATS="Artifact formats (space/comma-delimited: vhd vdi iso img) [%SAVED_X64_ARTIFACT_FORMAT%]: "
  if "%X64_ARTIFACT_FORMATS%"=="" set "X64_ARTIFACT_FORMATS=%SAVED_X64_ARTIFACT_FORMAT%"

  set "BUILD_UML_KERNEL=false"
  set "UML_DEFAULT=N"
  if /I "%SAVED_BUILD_UML_KERNEL%"=="true" set "UML_DEFAULT=Y"
  set "BUILD_UML_ANS=%UML_DEFAULT%"
  set /P BUILD_UML_ANS="Build optional User-Mode Linux kernel too? (y/N) [%UML_DEFAULT%]: "
  if /I "%BUILD_UML_ANS%"=="y" set "BUILD_UML_KERNEL=true"
) else (
  set "X64_ARTIFACT_FORMATS=img"
  set "BUILD_UML_KERNEL=false"
)

echo.
echo   (Last completed stage: %COMPLETED_STAGE% - default resumes at stage %DEFAULT_STAGE%)
echo.
echo Build Stages Overview:
echo   1-2:     Base rootfs and package manager setup
echo   3-4:     Portage overlay registration and Gentooha meta-package emerge
echo   5:       Compatibility layer and HA stack installation
echo   6:       Linux kernel build with feature validation (150+ flags enforced)
echo   7:       Bootloader setup (GRUB)
echo   8:       Home Assistant Supervisor and os-agent (live ebuilds from fork-first URLs)
echo   9-11:    Container runtime, AppArmor, and systemd services
echo   12:      Binary package cache generation for faster rebuilds
echo   13:      Final artifact manifest and packaging
echo.

:ask_stage
set "START_STAGE="
set /P START_STAGE="Start from stage (1-13) [%DEFAULT_STAGE%]: "
if "%START_STAGE%"=="" set "START_STAGE=%DEFAULT_STAGE%"
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
if "%START_STAGE%"=="13" goto stage_ok
echo Enter a number from 1 to 13.
goto ask_stage

:stage_ok
echo.

:: Only ask about cleaning when starting at stage 1
set "CLEAN_STATE=false"
if "%START_STAGE%"=="1" (
  set "CLEAN_ANS=N"
  set /P CLEAN_ANS="Clean prior stage state? (y/N) [N]: "
  if /I "%CLEAN_ANS%"=="y" set "CLEAN_STATE=true"
  echo.
)

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

:ask_binpkg
echo.
echo Build method:
echo   b  - Binary packages (fast, uses Gentoo binary host)
echo   s  - Compile from source (slow, full control)
echo   Note: packages with custom USE flags still fall back to source automatically.
echo.
set "BINPKG_ANS="
set /P BINPKG_ANS="Build method binary/source (b/s) [%DEF_BINPKG%]: "
if "%BINPKG_ANS%"=="" set "BINPKG_ANS=%DEF_BINPKG%"
if /I "%BINPKG_ANS%"=="b" (
  set "USE_BINPKG=true"
  goto binpkg_ok
)
if /I "%BINPKG_ANS%"=="s" (
  set "USE_BINPKG=false"
  goto binpkg_ok
)
echo Invalid choice. Use: b (binary) or s (source).
goto ask_binpkg

:binpkg_ok

:: Auto-resume information already applied above via DEFAULT_STAGE
echo.
echo ============================================================
echo  Build summary
echo    PLATFORM    = %PLATFORM%
echo    FLAVOR      = %FLAVOR%
if /I "%PLATFORM%"=="x64" echo    X64_FORMATS = %X64_ARTIFACT_FORMATS%
if /I "%PLATFORM%"=="x64" echo    UML_KERNEL  = %BUILD_UML_KERNEL%
echo    START_STAGE = %START_STAGE%  (last completed: %COMPLETED_STAGE%)
echo    CLEAN_STATE = %CLEAN_STATE%
echo    ARTIFACTS   = %ARTIFACT_ACTION% (a=archive, y=remove, n=keep)
echo    USE_BINPKG  = %USE_BINPKG%
echo.
echo  Gentooha Portage Emerges:
echo    - sys-kernel/gentooha-kernel-config-alpha (validates 150+ kernel features)
echo    - sys-apps/gentooha-compat (HA host compatibility, os-release, Docker config)
echo    - sys-apps/gentooha-supervisor-9999 (live ebuild, fork-first GitHub resolution)
echo    - sys-apps/gentooha-os-agent-9999 (live ebuild, Go-based os-agent)
echo    - gentooha/gentooha-alpha (meta-package: systemd, docker, apparmor, grub, all deps)
echo.
echo  All dependencies resolved via Portage emerge (no manual installation).
echo ============================================================
echo.

:ask_proceed
set "PROCEED=Y"
set /P PROCEED="Proceed? (Y/n) [Y]: "
if /I "%PROCEED%"=="n" ( echo Aborted. & pause & exit /b 0 )

:: Determine WSL distro to use for building
:: Prefer Debian (apt-based build host) over GentooHA.
set "WSL_DISTRO="
wsl -d Debian -u root -- echo ok >nul 2>&1 && set "WSL_DISTRO=Debian"
if "%WSL_DISTRO%"=="" (
  wsl -d GentooHA -u root -- echo ok >nul 2>&1 && set "WSL_DISTRO=GentooHA"
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

wsl -d %WSL_DISTRO% -u root -- bash -c "export PLATFORM=%PLATFORM% FLAVOR=%FLAVOR% START_STAGE=%START_STAGE% CLEAN_STATE=%CLEAN_STATE% ARTIFACT_ACTION=%ARTIFACT_ACTION% USE_BINPKG=%USE_BINPKG% X64_ARTIFACT_FORMATS='%X64_ARTIFACT_FORMATS%' BUILD_UML_KERNEL=%BUILD_UML_KERNEL%; cd '%WSL_PATH%'; bash build.sh --non-interactive"
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
if /I "%PLATFORM%"=="x64" (
  echo Artifacts selected: %X64_ARTIFACT_FORMATS%
) else (
  echo Artifact: gentooha-%PLATFORM%-%FLAVOR%.img
)
echo Location: %WIN_PATH%artifacts\ and /var/lib/ha-gentoo-hybrid/artifacts/ inside WSL
echo.
pause
