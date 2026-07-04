@echo off
setlocal
title Good-Badminton Mobile Backend

set "PROJECT_DIR=D:\py\Good-Badminton"
set "PYTHON_EXE=C:\Users\jiale\miniconda3\envs\badminton\python.exe"
set "HOST=0.0.0.0"
set "PORT=8001"

echo ==================================================
echo   Good-Badminton Mobile Backend
echo ==================================================
echo.

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python environment was not found:
    echo %PYTHON_EXE%
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

echo Starting backend:
echo   http://127.0.0.1:%PORT%
echo   http://YOUR_COMPUTER_IP:%PORT%
echo.
echo Keep this window open while the mobile app or phone browser is using the backend.
echo.

"%PYTHON_EXE%" -m uvicorn backend_api:app --host %HOST% --port %PORT%

set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
    echo [INFO] The backend stopped with exit code %EXIT_CODE%.
) else (
    echo The backend stopped normally.
)
echo.
pause
exit /b %EXIT_CODE%
