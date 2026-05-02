repos/home-assistant/apps-example@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "BASE=%ROOT%repos\home-assistant"
set "TMP_STATUS=%TEMP%\repo_change_status.tmp"
set "TMP_REPOS=%TEMP%\repo_change_repos.tmp"
set "FOUND_ANY=0"

if not exist "%BASE%" (
    echo ERROR: Expected folder not found: "%BASE%"
    exit /b 1
)

where git >nul 2>nul
if errorlevel 1 (
    echo ERROR: git was not found in PATH.
    exit /b 1
)

if exist "%TMP_REPOS%" del /f /q "%TMP_REPOS%" >nul 2>nul

echo ============================================================
echo Changed Files By Repo
echo ============================================================
echo.

for /d %%R in ("%BASE%\*") do (
    if exist "%%~fR\.git" (
        git -C "%%~fR" status --porcelain > "%TMP_STATUS%" 2>nul
        for %%S in ("%TMP_STATUS%") do (
            if %%~zS gtr 0 (
                set "FOUND_ANY=1"
                echo [%%~nR]
                type "%TMP_STATUS%"
                echo.
                >> "%TMP_REPOS%" echo repos/home-assistant/%%~nR
            )
        )
    )
)

if "%FOUND_ANY%"=="0" (
    echo No changed files found in cloned repos under "%BASE%".
    echo.
    echo ============================================================
    echo Changed Repos
    echo ============================================================
    echo None
    if exist "%TMP_STATUS%" del /f /q "%TMP_STATUS%" >nul 2>nul
    if exist "%TMP_REPOS%" del /f /q "%TMP_REPOS%" >nul 2>nul
    exit /b 0
)

echo ============================================================
echo Changed Repos
echo ============================================================
sort "%TMP_REPOS%" | findstr /v "^$"

if exist "%TMP_STATUS%" del /f /q "%TMP_STATUS%" >nul 2>nul
if exist "%TMP_REPOS%" del /f /q "%TMP_REPOS%" >nul 2>nul

exit /b 0