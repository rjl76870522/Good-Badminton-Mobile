@echo off
setlocal
title Good-Badminton Public Tunnel

set "PROJECT_DIR=D:\py\Good-Badminton"
set "CLOUDFLARED_EXE=D:\tools\cloudflared\cloudflared.exe"
set "LOCAL_BACKEND=http://127.0.0.1:8001"
set "MAX_TUNNEL_ATTEMPTS=5"
set "RETRY_SECONDS=5"

echo ==================================================
echo   Good-Badminton Public HTTPS Tunnel
echo ==================================================
echo.

if not exist "%CLOUDFLARED_EXE%" (
    echo [ERROR] cloudflared was not found:
    echo %CLOUDFLARED_EXE%
    echo.
    echo Install path used on this computer:
    echo D:\tools\cloudflared\cloudflared.exe
    echo.
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"

echo Checking local backend:
echo   %LOCAL_BACKEND%/api/health
curl.exe -fsS "%LOCAL_BACKEND%/api/health" >nul
if errorlevel 1 (
    echo.
    echo [ERROR] Local backend is not running.
    echo Start it first:
    echo   D:\py\Good-Badminton\start_mobile_backend.bat
    echo.
    pause
    exit /b 1
)

echo.
echo Starting public tunnel for:
echo   %LOCAL_BACKEND%
echo.
echo Copy the generated https://*.trycloudflare.com URL as the app baseUrl.
echo Keep this window open while the frontend is using the tunnel.
echo.

set /a ATTEMPT=1

:start_tunnel
echo Tunnel attempt %ATTEMPT%/%MAX_TUNNEL_ATTEMPTS%
"%CLOUDFLARED_EXE%" tunnel --url "%LOCAL_BACKEND%"
set "TUNNEL_EXIT_CODE=%ERRORLEVEL%"

if "%TUNNEL_EXIT_CODE%"=="0" goto tunnel_stopped

echo.
echo [WARN] cloudflared stopped with exit code %TUNNEL_EXIT_CODE%.
echo This is often a temporary Cloudflare quick-tunnel error.
if %ATTEMPT% GEQ %MAX_TUNNEL_ATTEMPTS% goto tunnel_failed
set /a ATTEMPT+=1
echo Retrying in %RETRY_SECONDS% seconds...
timeout /t %RETRY_SECONDS% /nobreak >nul
echo.
goto start_tunnel

:tunnel_failed
echo.
echo [ERROR] Could not start a public tunnel after %MAX_TUNNEL_ATTEMPTS% attempts.
echo You can still test on the same WiFi with:
echo   http://YOUR_COMPUTER_IP:8001
echo Or try again later; quick trycloudflare tunnels can fail temporarily.
pause
exit /b %TUNNEL_EXIT_CODE%

:tunnel_stopped
echo.
echo Tunnel stopped.
pause
exit /b 0
