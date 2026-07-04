@echo off
setlocal
title Good-Badminton Mobile Backend + Public Tunnel

set "PROJECT_DIR=D:\py\Good-Badminton"
set "PYTHON_EXE=C:\Users\jiale\miniconda3\envs\badminton\python.exe"
set "CLOUDFLARED_EXE=D:\tools\cloudflared\cloudflared.exe"
set "PORT=8001"
set "LOCAL_BACKEND=http://127.0.0.1:%PORT%"

echo ==================================================
echo   Good-Badminton Mobile Backend + Public Tunnel
echo ==================================================
echo.
echo This script is for the mobile/competition backend only:
echo   backend_api.py on port %PORT%
echo.

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python environment was not found:
    echo %PYTHON_EXE%
    echo.
    pause
    exit /b 1
)

if not exist "%CLOUDFLARED_EXE%" (
    echo [ERROR] cloudflared was not found:
    echo %CLOUDFLARED_EXE%
    echo.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%\backend_api.py" (
    echo [ERROR] backend_api.py was not found:
    echo %PROJECT_DIR%\backend_api.py
    echo.
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"

curl.exe -fsS "%LOCAL_BACKEND%/api/health" >nul 2>nul
if not errorlevel 1 (
    echo Mobile backend is already running:
    echo   %LOCAL_BACKEND%
    goto backend_ready
)

echo Starting mobile backend window...
start "Good-Badminton Mobile Backend 8001" cmd /k call "%PROJECT_DIR%\start_mobile_backend.bat"

echo Waiting for backend health:
echo   %LOCAL_BACKEND%/api/health
for /l %%i in (1,1,35) do (
    curl.exe -fsS "%LOCAL_BACKEND%/api/health" >nul 2>nul
    if not errorlevel 1 goto backend_ready
    timeout /t 1 /nobreak >nul
)

echo.
echo [ERROR] Mobile backend did not become ready on %LOCAL_BACKEND%.
echo Check the backend window for errors.
echo.
pause
exit /b 1

:backend_ready
echo.
echo Backend is ready.
echo Starting public tunnel window...
start "Good-Badminton Public HTTPS Tunnel" cmd /k call "%PROJECT_DIR%\start_public_tunnel.bat"

echo.
echo Next:
echo   1. In the tunnel window, copy the generated https://*.trycloudflare.com URL.
echo   2. In the AI羽毛球 app, set backend address to that URL.
echo   3. Do not add /docs or /api to the app backend address.
echo.
echo Keep both opened windows running while testing.
echo.
pause
exit /b 0
