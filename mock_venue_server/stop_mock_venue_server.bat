@echo off
setlocal
cd /d "%~dp0.."

if not exist "mock_venue_server\.server.pid" (
  echo No managed Mock Venue Server PID file was found.
  echo If port 9000 is still occupied, close the terminal that started it manually.
  if /I not "%~1"=="--no-pause" pause
  exit /b 1
)

if exist "mock_venue_server\.tunnel.pid" (
  for /f %%i in (mock_venue_server\.tunnel.pid) do set TUNNEL_PID=%%i
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Id %TUNNEL_PID% -Force -ErrorAction SilentlyContinue"
  del /q "mock_venue_server\.tunnel.pid"
  echo Public tunnel stopped. PID: %TUNNEL_PID%
)

for /f %%i in (mock_venue_server\.server.pid) do set SERVER_PID=%%i
powershell -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Id %SERVER_PID% -Force -ErrorAction SilentlyContinue"
del /q "mock_venue_server\.server.pid"
echo Mock Venue Server stopped (PID %SERVER_PID%).
if /I not "%~1"=="--no-pause" pause
