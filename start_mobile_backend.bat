@echo off
chcp 65001 >nul
title Good-Badminton Mobile Backend

cd /d "C:\Users\lanld\Good-Badminton"

echo ==================================================
echo   Good-Badminton Mobile Backend
echo ==================================================
echo.
echo Keep this window open while the mobile app is using the backend.
echo.
echo Mobile API: http://172.29.11.85:8001
echo.
python -m uvicorn backend_api:app --host 0.0.0.0 --port 8001
pause
