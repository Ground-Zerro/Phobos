@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.

setlocal enabledelayedexpansion
set BUILDDIR=%~dp0
set PATH=%BUILDDIR%.deps\bin;%BUILDDIR%.deps;%PATH%
set PATHEXT=.exe
cd /d %BUILDDIR% || exit /b 1

if exist .deps\prepared goto :build
:installdeps
	rmdir /s /q .deps 2> NUL
	mkdir .deps || goto :error
	cd .deps || goto :error
	call :download go.zip https://download.wireguard.com/windows-toolchain/distfiles/go1.26.2-windows_amd64_2026-04-20.zip 79b5d5ff6f2718dfe25e199cda314d174ecf5bb19f0f2d777aec089d09a12620 "--strip-components 1" || goto :error
	rem Mirror of https://github.com/mstorsjo/llvm-mingw/releases/download/20260311/llvm-mingw-20260311-ucrt-x86_64.zip
	call :download llvm-mingw-ucrt.zip https://download.wireguard.com/windows-toolchain/distfiles/llvm-mingw-20260311-ucrt-x86_64.zip dd4c67d98959479c7be2fb6709ba074475991590848cb9d0eb2620be06b182e1 "--strip-components 1" || goto :error
	rem Mirror of https://sourceforge.net/projects/ezwinports/files/make-4.2.1-without-guile-w32-bin.zip
	call :download make.zip https://download.wireguard.com/windows-toolchain/distfiles/make-4.2.1-without-guile-w32-bin.zip 30641be9602712be76212b99df7209f4f8f518ba764cf564262bc9d6e4047cc7 "--strip-components 1 bin" || goto :error
	call :download wireguard-tools.zip https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-06a99cce2c9998f53eb30d2f258a9e5ff286445b.zip b7a73e027cee3127f3cccba8ad3a08ea61ccd42d3ea5c28c548a8e0ec9e10cf6 "--exclude wg-quick --strip-components 1" || goto :error
	call :download wireguard-nt.zip https://download.wireguard.com/wireguard-nt/wireguard-nt-1.1.zip dceb30a9bc4be48cce0f74160fc88a585a2c2627366e8f846fc6658f9038dace || goto :error
	call :download wintun.zip https://www.wintun.net/builds/wintun-0.14.1.zip 07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51 || goto :error
	copy /y NUL prepared > NUL || goto :error
	cd .. || goto :error

:build
	for /f "tokens=3" %%a in ('findstr /r "Number.*=.*[0-9.]*" .\version\version.go') do set PHOBOS_VERSION=%%a
	set PHOBOS_VERSION=%PHOBOS_VERSION:"=%
	for /f "tokens=1-4" %%a in ("%PHOBOS_VERSION:.= % 0 0 0") do set PHOBOS_VERSION_ARRAY=%%a,%%b,%%c,%%d
	set GOOS=windows
	set GOARM=7
	set GOPATH=%BUILDDIR%.deps\gopath
	set GOROOT=%BUILDDIR%.deps
	if "%GoGenerate%"=="yes" (
		echo [+] Regenerating files
		go generate ./... || exit /b 1
	)
	call :build_plat x86 i686 386 || goto :error
	call :build_plat amd64 x86_64 amd64 || goto :error
	call :build_plat arm64 aarch64 arm64 || goto :error

:sign
	if exist .\sign.bat call .\sign.bat
	if "%SigningProvider%"=="" goto :success
	if "%TimestampServer%"=="" goto :success
	echo [+] Signing
	signtool sign %SigningProvider% /fd sha256 /tr "%TimestampServer%" /td sha256 /d Phobos x86\phobos.exe x86\wg.exe amd64\phobos.exe amd64\wg.exe arm64\phobos.exe arm64\wg.exe || goto :error

:success
	echo [+] Success. Launch phobos.exe.
	exit /b 0

:download
	echo [+] Downloading %1
	curl -#fLo %1 %2 || exit /b 1
	echo [+] Verifying %1
	for /f %%a in ('CertUtil -hashfile %1 SHA256 ^| findstr /r "^[0-9a-f]*$"') do if not "%%a"=="%~3" exit /b 1
	echo [+] Extracting %1
	tar -xf %1 %~4 || exit /b 1
	echo [+] Cleaning up %1
	del %1 || exit /b 1
	goto :eof

:build_plat
	set GOARCH=%~3
	mkdir %1 >NUL 2>&1
	echo [+] Assembling resources %1
	%~2-w64-mingw32-windres -I ".deps\wireguard-nt\bin\%~1" -I ".deps\wintun\bin\%~1" -DPHOBOS_VERSION_ARRAY=%PHOBOS_VERSION_ARRAY% -DPHOBOS_VERSION_STR=%PHOBOS_VERSION% -i resources.rc -o "resources_%~3.syso" -O coff -c 65001 || exit /b %errorlevel%
	echo [+] Building program %1
	set CGO_ENABLED=1
	set CC=%~2-w64-mingw32-gcc
	go build -tags load_dll_from_rsrc -ldflags="-H windowsgui -s -w" -trimpath -buildvcs=false -v -o "%~1\phobos.exe" || exit /b 1
	if not exist "%~1\wg.exe" (
		echo [+] Building command line tools %1
		del .deps\src\*.exe .deps\src\*.o .deps\src\wincompat\*.o .deps\src\wincompat\*.lib 2> NUL
		set LDFLAGS=-s
		make --no-print-directory -C .deps\src PLATFORM=windows CC=%~2-w64-mingw32-gcc WINDRES=%~2-w64-mingw32-windres V=1 RUNSTATEDIR= SYSTEMDUNITDIR= -j%NUMBER_OF_PROCESSORS% || exit /b 1
		move /Y .deps\src\wg.exe "%~1\wg.exe" > NUL || exit /b 1
	)
	goto :eof

:error
	echo [-] Failed with error #%errorlevel%.
	cmd /c exit %errorlevel%
