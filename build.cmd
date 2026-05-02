@echo off
setlocal EnableExtensions DisableDelayedExpansion

echo ============================================================
echo  GentooHA Build Launcher
echo ============================================================
echo.
echo Platforms:
echo   x64      - Generic PC / VM  (produces .iso)
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
echo.

:ask_flavor
set "FLAVOR="
set /P FLAVOR="Flavor [live]: "
if "%FLAVOR%"=="" set "FLAVOR=live"
if /I "%FLAVOR%"=="live"      goto flavor_ok
if /I "%FLAVOR%"=="installer" goto flavor_ok
echo Invalid flavor. Choose: live  installer
goto ask_flavor

:flavor_ok
echo.

:ask_stage
set "START_STAGE="
set /P START_STAGE="Start from stage (1-10) [1]: "
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
echo Enter a number from 1 to 10.
goto ask_stage

:stage_ok
echo.

:ask_clean
set "CLEAN_ANS=N"
set /P CLEAN_ANS="Clean prior stage state? (y/N) [N]: "
set "CLEAN_STATE=false"
if /I "%CLEAN_ANS%"=="y" set "CLEAN_STATE=true"

echo.
echo ============================================================
echo  Build summary
echo    PLATFORM    = %PLATFORM%
echo    FLAVOR      = %FLAVOR%
echo    START_STAGE = %START_STAGE%
echo    CLEAN_STATE = %CLEAN_STATE%
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
set "WSL_PATH=/mnt/c%WIN_PATH:\=/%"
set "WSL_PATH=%WSL_PATH::=%"
:: Strip trailing slash
if "%WSL_PATH:~-1%"=="/" set "WSL_PATH=%WSL_PATH:~0,-1%"

wsl -d %WSL_DISTRO% -- bash -c "export PLATFORM=%PLATFORM% FLAVOR=%FLAVOR% START_STAGE=%START_STAGE% CLEAN_STATE=%CLEAN_STATE%; cd '%WSL_PATH%'; bash build.sh --non-interactive"
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
  if /I not "!RUN_IMPORT!"=="n" (
    call "%~dp0import_and_boot_gentooha.cmd" 1
  )
)

echo.
echo Build complete.
echo Artifact: gentooha-%PLATFORM%-%FLAVOR%.%ARTIFACT_EXT%
echo Location: %WIN_PATH%repos\home-assistant\artifacts\ (or check /var/lib/ha-gentoo-hybrid/artifacts/ inside WSL)
echo.
pause
