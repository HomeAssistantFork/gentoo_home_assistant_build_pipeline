@echo off
setlocal

call "%~dp0import_and_boot_gentooha.cmd" %*
exit /b %ERRORLEVEL%
