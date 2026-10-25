@echo off
rem Windows 10+ batch file (uses the built-in curl.exe and PowerShell for JSON parsing).
setlocal enabledelayedexpansion

set "BASE_URL=https://ironbrew1.com"
set "API_KEY=IB1-APIKEYHERE"

set "INPUT_PATH=input.lua"
set "OUTPUT_PATH=output.lua"

set "QUERY=platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

set /a RETRY_DELAY=5
set /a MAX_WAIT=240
set /a MAX_FAILS=3

set "RESPONSE=%TEMP%\ib1_response.json"

curl.exe -sS -o "%RESPONSE%" -w "%%{http_code}" -X POST "%BASE_URL%/obfuscate?%QUERY%" -H "Key: %API_KEY%" -H "Content-Type: text/plain" --data-binary "@%INPUT_PATH%" > "%TEMP%\ib1_code.txt"
set /p CODE=<"%TEMP%\ib1_code.txt"
if not "%CODE:~0,1%"=="2" (
    echo Unable to queue obfuscation: %CODE% 1>&2
    exit /b 1
)

call :field "%RESPONSE%" uploadGuid GUID
call :field "%RESPONSE%" statusUrl STATUS_URL
echo Obfuscation started with GUID: %GUID%

set /a ELAPSED=0
set /a FAILS=0
set /a WAIT=0

:poll
set /a WAIT+=RETRY_DELAY
timeout /t %WAIT% /nobreak >nul
set /a ELAPSED+=WAIT

curl.exe -sS -o "%RESPONSE%" -w "%%{http_code}" "%BASE_URL%%STATUS_URL%" -H "Key: %API_KEY%" > "%TEMP%\ib1_code.txt"
set /p CODE=<"%TEMP%\ib1_code.txt"
if not "%CODE:~0,1%"=="2" (
    set /a FAILS+=1
    echo Status check failed with status: %CODE% ^(!FAILS!/%MAX_FAILS%^)
    if !FAILS! geq %MAX_FAILS% goto :failed_checks
    if !ELAPSED! geq %MAX_WAIT% goto :failed_checks
    goto :poll
)

call :field "%RESPONSE%" status STATE

if "%STATE%"=="completed" goto :download
if "%STATE%"=="failed" goto :failed_job
if %ELAPSED% geq %MAX_WAIT% goto :failed_job

set /a NEXT=RETRY_DELAY+WAIT
echo Obfuscation is still in progress. Elapsed time: %ELAPSED% seconds. Checking again in %NEXT% seconds.
goto :poll

:download
echo Obfuscation completed in %ELAPSED% seconds
call :field "%RESPONSE%" downloadUrl DOWNLOAD_URL
curl.exe -sS -f -o "%OUTPUT_PATH%" "%BASE_URL%%DOWNLOAD_URL%" -H "Key: %API_KEY%"
if errorlevel 1 (
    echo Download failed 1>&2
    exit /b 1
)
echo Saved obfuscated script to %OUTPUT_PATH%
exit /b 0

:failed_checks
echo Obfuscation failed ^(fails: %FAILS% ^| elapsed time: %ELAPSED%^) 1>&2
exit /b 1

:failed_job
echo Obfuscation failed ^(status: %STATE% ^| elapsed time: %ELAPSED%^) 1>&2
exit /b 1

rem :field <json file> <name> <variable>  - reads one string field from a JSON file
:field
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "(Get-Content -Raw '%~1' | ConvertFrom-Json).%~2"`) do set "%~3=%%v"
exit /b 0
