@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

echo [configure] Root: %ROOT%

if exist "%ROOT%\.gitmodules" (
    echo [configure] Detected .gitmodules. Restoring submodules first...
    git -C "%ROOT%" submodule sync --recursive
    if %ERRORLEVEL% NEQ 0 goto :error
    git -C "%ROOT%" submodule update --init --recursive
    if %ERRORLEVEL% NEQ 0 goto :error
)

where bash >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [configure] Running configure.sh via bash...
    bash "%ROOT%\configure.sh" %*
    if %ERRORLEVEL% NEQ 0 goto :error
    goto :done
)

where wsl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [configure] ERROR: Neither bash nor wsl is available.
    goto :error
)

for /f "delims=" %%P in ('wsl wslpath "%ROOT%"') do set "ROOT_WSL=%%P"
if "%ROOT_WSL%"=="" (
    echo [configure] ERROR: Failed to convert path for WSL.
    goto :error
)

echo [configure] Running configure.sh via WSL Debian...
wsl -d Debian -u root -- bash -lc "cd '%ROOT_WSL%' && bash ./configure.sh %*"
if %ERRORLEVEL% NEQ 0 (
    echo [configure] Debian WSL run failed, trying default WSL distro...
    wsl -- bash -lc "cd '%ROOT_WSL%' && bash ./configure.sh %*"
    if %ERRORLEVEL% NEQ 0 goto :error
)

goto :done

:error
echo [configure] Failed.
exit /b 1

:done
echo [configure] Normalizing Windows submodule worktrees for clean status...
for %%R in (addons android brands buildroot operating-system version) do (
    if exist "%ROOT%\repos\home-assistant\%%R\.git" (
        git -C "%ROOT%\repos\home-assistant\%%R" config core.symlinks false
        git -C "%ROOT%\repos\home-assistant\%%R" reset --hard HEAD >nul 2>&1
        git -C "%ROOT%\repos\home-assistant\%%R" clean -fd >nul 2>&1
        echo [configure] %%R normalized.
    )
)

echo [configure] Completed successfully.
exit /b 0
