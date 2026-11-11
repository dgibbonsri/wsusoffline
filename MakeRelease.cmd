@echo off
rem *** Author: T. Wittrock, Kiel ***
rem ***
rem *** Builds a release in one step, next to this repository:
rem ***   ..\wsusoffline-release\               ready to run (UpdateGenerator.exe)
rem ***   ..\wsusofflineCE<version>.zip         archive for handing out
rem ***   ..\wsusofflineCE<version>_hashes.txt  hashes of the archive
rem ***
rem *** Usage: MakeRelease.cmd [VersionNumber]
rem *** Without a version number, the one in static\SelfUpdateVersion-this.txt is used.
rem *** The ready-to-run folder is updated in place: downloaded updates, logs and settings
rem *** in it are kept. Only tools that are part of Windows or bundled in this repository are
rem *** used (the zip is made with Windows' built-in tar.exe; nothing needs to be installed).

verify other 2>nul
setlocal enableextensions
if errorlevel 1 goto NoExtensions

rem *** Keep the window open at the end when started by double-click from Explorer ***
set PAUSE_AT_END=
rem (copy CMDCMDLINE first: string substitution on it changes the variable itself)
setlocal enabledelayedexpansion
set "CMDLINE_ORIG=!CMDCMDLINE!"
set "CMDLINE_CHECK=!CMDLINE_ORIG:%~f0=!"
if /i not "!CMDLINE_CHECK!"=="!CMDLINE_ORIG!" (endlocal & set PAUSE_AT_END=1) else (endlocal)

rem *** Version number: first parameter, or else taken from static\SelfUpdateVersion-this.txt ***
set RELEASE_VER=%~1
if "%RELEASE_VER%"=="" (
  if exist "%~dp0static\SelfUpdateVersion-this.txt" (
    for /F "usebackq tokens=1 delims=," %%i in ("%~dp0static\SelfUpdateVersion-this.txt") do set RELEASE_VER=%%i
  )
)
if "%RELEASE_VER%"=="" goto NoParam

rem *** Output locations (parent folder of this repository) ***
for %%i in ("%~dp0..") do set OUT_DIR=%%~fi
set RELEASE_DIR=%OUT_DIR%\wsusoffline-release
set ZIP_FILE=%OUT_DIR%\wsusofflineCE%RELEASE_VER%.zip
set HASH_FILE=%OUT_DIR%\wsusofflineCE%RELEASE_VER%_hashes.txt

if "%TEMP%"=="" goto NoTemp
pushd "%TEMP%"
if errorlevel 1 goto NoTempDir
popd
set STAGE_DIR=%TEMP%\wsusoffline

rem *** Copy everything a release needs into a temporary staging folder ***
rem *** (exclude\ExcludeList-ReleaseTree.txt lists the build-only files that are left out) ***
if exist "%STAGE_DIR%" rd /S /Q "%STAGE_DIR%"
md "%STAGE_DIR%"
echo Copying scripts and binaries...
pushd "%~dps0"
xcopy *.* "%STAGE_DIR%" /E /Q /Y /EXCLUDE:exclude\ExcludeList-ReleaseTree.txt
popd

rem *** Compile the two AutoIt programs with the bundled compiler ***
rem *** (no compression / UPX packing: avoids false alarms from virus scanners) ***
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (
  if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set AUT2EXE_EXE=Aut2exe_x64.exe) else (set AUT2EXE_EXE=Aut2Exe.exe)
)
if not exist "%~dps0bin\%AUT2EXE_EXE%" goto CompileError
echo Compiling UpdateGenerator.exe and UpdateInstaller.exe...
pushd "%STAGE_DIR%"
for %%i in (UpdateGenerator.au3 client\UpdateInstaller.au3) do "%~dps0bin\%AUT2EXE_EXE%" /in "%%i" /icon "%~dps0ico\okshield.ico" /x86 /comp 0 /nopack
popd
if not exist "%STAGE_DIR%\UpdateGenerator.exe" goto CompileError
if not exist "%STAGE_DIR%\client\UpdateInstaller.exe" goto CompileError

rem *** Update the ready-to-run folder in place (keeps downloads, logs and settings) ***
echo Updating ready-to-run folder "%RELEASE_DIR%"...
xcopy "%STAGE_DIR%" "%RELEASE_DIR%\" /E /I /Q /Y >nul
if errorlevel 1 goto CopyError

rem *** Remove files of features that were removed from this build (an older ready-to-run ***
rem *** folder may still contain them, because the folder is updated in place) ***
for %%f in (cmd\CheckOUVersion.cmd cmd\UpdateOU.cmd cmd\UpdateOU.new cmd\ActivateAria2Downloads.cmd cmd\RemoveGermanLanguageSupport.cmd static\StaticDownloadLinks-aria2.txt static\SelfUpdateVersion-static.txt static\SelfUpdateVersion-recent.txt bin\unzip.exe bin\Info-Zip-License.txt bin\upx.exe bin\mkisofs.exe bin\aria2c.exe client\bin\unzip.exe client\bin\IfAdmin.exe client\bin\IfAdmin.cpp doc\faq-deu.txt sh\documentation\Installationsanleitung.txt) do (
  if exist "%RELEASE_DIR%\%%f" del "%RELEASE_DIR%\%%f"
)
if exist "%RELEASE_DIR%\static\sdd\nul" rd /S /Q "%RELEASE_DIR%\static\sdd"

rem *** Create the zip archive (Windows' built-in tar.exe) and its hash list ***
set ZIP_DONE=
if not exist %SystemRoot%\System32\tar.exe (
  echo.
  echo Warning: Windows' built-in tar.exe was not found ^(it is part of Windows 10 version 1803
  echo          and later^), so the zip archive cannot be created.
  echo          The ready-to-run folder has been built and can be used as is.
  goto Cleanup
)
if exist "%ZIP_FILE%" del "%ZIP_FILE%"
if exist "%HASH_FILE%" del "%HASH_FILE%"
echo Creating release archive "%ZIP_FILE%"...
pushd "%TEMP%"
%SystemRoot%\System32\tar.exe -a -c -f "%ZIP_FILE%" wsusoffline
popd
if not exist "%ZIP_FILE%" goto ZipError
echo Creating hash list "%HASH_FILE%"...
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set HASHDEEP_EXE=hashdeep64.exe) else (
  if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" (set HASHDEEP_EXE=hashdeep64.exe) else (set HASHDEEP_EXE=hashdeep.exe)
)
pushd "%OUT_DIR%"
"%~dps0client\bin\%HASHDEEP_EXE%" -c md5,sha1,sha256 -b "wsusofflineCE%RELEASE_VER%.zip" >"%TEMP%\wsusofflineCE%RELEASE_VER%.mds"
%SystemRoot%\System32\findstr.exe /L /I /C:## /V "%TEMP%\wsusofflineCE%RELEASE_VER%.mds" >"%HASH_FILE%"
del "%TEMP%\wsusofflineCE%RELEASE_VER%.mds"
popd
set ZIP_DONE=1

:Cleanup
echo.
echo Done.
echo   Run it:       "%RELEASE_DIR%\UpdateGenerator.exe"
echo   Install side: "%RELEASE_DIR%\client\UpdateInstaller.exe"
if "%ZIP_DONE%"=="1" (
  echo   Archive:      "%ZIP_FILE%"
  echo   Hashes:       "%HASH_FILE%"
) else (
  echo   Archive:      NOT CREATED - Windows' built-in tar.exe is required for the zip archive
  echo                 ^(Windows 10 version 1803 or later^). Only the zip is missing;
  echo                 the folder above is complete.
)
echo.
goto EoF

:NoExtensions
echo.
echo ERROR: No command extensions available.
echo.
goto EoF

:NoParam
echo.
echo ERROR: No version number given, and none found in static\SelfUpdateVersion-this.txt.
echo Usage: %~n0 [VersionNumber]
echo.
goto EoF

:NoTemp
echo.
echo ERROR: Environment variable TEMP not set.
echo.
goto EoF

:NoTempDir
echo.
echo ERROR: Directory "%TEMP%" not found.
echo.
goto EoF

:CompileError
echo.
echo ERROR: Compiling the AutoIt scripts failed; UpdateGenerator.exe or UpdateInstaller.exe is missing.
echo Nothing was changed in "%RELEASE_DIR%".
echo.
goto EoF

:CopyError
echo.
echo ERROR: Could not copy the release into "%RELEASE_DIR%".
echo Close any running UpdateGenerator.exe / UpdateInstaller.exe from that folder and try again.
echo.
goto EoF

:ZipError
echo.
echo ERROR: Creating "%ZIP_FILE%" failed.
echo.
goto EoF

:EoF
if defined STAGE_DIR (
  if exist "%STAGE_DIR%" rd /S /Q "%STAGE_DIR%"
)
if "%PAUSE_AT_END%"=="1" pause
endlocal
