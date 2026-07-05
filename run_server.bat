@echo off
chcp 65001 >nul
cd /d "C:\Users\lanld\Good-Badminton"
echo Good-Badminton 后端启动中...
echo 访问 http://localhost:8000 测试
echo 手机同WiFi访问 http://172.29.11.85:8000
echo.
python -m uvicorn server.main:app --host 0.0.0.0 --port 8000 --reload
pause
