@echo off
setlocal

set "CLOUDFLARED_EXE=D:\tools\cloudflared\cloudflared.exe"
set "TUNNEL_NAME=good-badminton"

echo Starting named Cloudflare Tunnel: %TUNNEL_NAME%
echo Keep this window open while the app is using the fixed domain.
echo.

"%CLOUDFLARED_EXE%" tunnel run "%TUNNEL_NAME%"

echo.
echo Tunnel stopped.
pause
