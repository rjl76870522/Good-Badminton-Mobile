@echo off
setlocal
title Good-Badminton Public Tunnel

set "PROJECT_DIR=D:\py\Good-Badminton"
set "CLOUDFLARED_EXE=D:\tools\cloudflared\cloudflared.exe"
set "LOCAL_BACKEND=http://127.0.0.1:8001"

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

"%CLOUDFLARED_EXE%" tunnel --url "%LOCAL_BACKEND%"

echo.
echo Tunnel stopped.
pause
