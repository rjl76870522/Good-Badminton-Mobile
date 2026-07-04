@echo off
setlocal
title Good-Badminton Full Backend

set "PROJECT_DIR=D:\py\Good-Badminton"
set "PYTHON_EXE=C:\Users\jiale\miniconda3\envs\badminton\python.exe"
set "HOST=0.0.0.0"
set "PORT=8000"

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python environment was not found:
    echo %PYTHON_EXE%
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"
echo Starting Good-Badminton full backend...
echo Local URL: http://127.0.0.1:%PORT%
echo LAN URL:   http://YOUR_COMPUTER_IP:%PORT%
echo.
"%PYTHON_EXE%" -m uvicorn server.main:app --host %HOST% --port %PORT% --reload
pause
