@echo off
chcp 65001 >nul
title Good-Badminton WebUI

cd /d "C:\Users\lanld\Good-Badminton"

echo ==================================================
echo   Good-Badminton WebUI
echo ==================================================
echo.
echo Starting the WebUI. Please wait...
echo.
echo Browser: http://127.0.0.1:7860
echo.
start "" http://127.0.0.1:7860
python -m webui.app
pause
