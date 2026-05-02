@echo off
setlocal

call "%~dp0scripts\windows\import_and_boot_gentooha.cmd" %*
exit /b %ERRORLEVEL%
