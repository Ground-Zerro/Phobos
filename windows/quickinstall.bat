@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.

setlocal
cd /d %~dp0 || exit /b 1
echo [+] Building phobos.exe
call .\build.bat || exit /b 1
echo [+] Building installer
call .\installer\build.bat || exit /b 1
echo [+] Uninstalling old versions
for /f %%a in ('reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall /s /d /c /e /f Phobos ^| findstr CurrentVersion\Uninstall') do msiexec /qb /x %%~na
echo [+] Installing new version
for /f "tokens=3" %%a in ('findstr /r "Number.*=.*[0-9.]*" .\version\version.go') do set PHOBOS_VERSION=%%a
set PHOBOS_VERSION=%PHOBOS_VERSION:"=%
msiexec /qb /i installer\dist\phobos-%PROCESSOR_ARCHITECTURE%-%PHOBOS_VERSION%.msi
