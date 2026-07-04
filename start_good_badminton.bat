@echo off
setlocal
title Good-Badminton Launcher

set "PROJECT_DIR=D:\py\Good-Badminton"
set "PYTHON_EXE=C:\Users\jiale\miniconda3\envs\badminton\python.exe"
set "WEB_URL=http://127.0.0.1:7860"

echo ==================================================
echo   Good-Badminton WebUI Launcher
echo ==================================================
echo.

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python environment was not found:
    echo %PYTHON_EXE%
    echo.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%\webui\app.py" (
    echo [ERROR] Good-Badminton project was not found:
    echo %PROJECT_DIR%
    echo.
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"

echo Starting the WebUI. Please wait...
echo Browser address: %WEB_URL%
echo.
echo Keep this window open while analyzing a video.
echo Press Ctrl+C in this window when you want to stop the server.
echo.

start "" /min powershell.exe -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 5; Start-Process '%WEB_URL%'"
"%PYTHON_EXE%" -m webui.app

set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" (
    echo [INFO] The server stopped with exit code %EXIT_CODE%.
) else (
    echo The server stopped normally.
)
echo.
pause
exit /b %EXIT_CODE%
