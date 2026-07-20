@echo off
setlocal
cd /d "%~dp0.."

if exist "mock_venue_server\.server.pid" (
  echo Mock Venue Server may already be running. Use stop_mock_venue_server.bat first.
  pause
  exit /b 1
)

echo Starting local Mock Venue Server on http://0.0.0.0:9000 ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath python -ArgumentList '-m','uvicorn','mock_venue_server.main:app','--host','0.0.0.0','--port','9000' -WorkingDirectory '%CD%' -WindowStyle Hidden -PassThru; Set-Content -LiteralPath 'mock_venue_server\.server.pid' -Value $p.Id; Write-Host ('Started PID: ' + $p.Id)"
if errorlevel 1 (
  echo Failed to start Mock Venue Server.
  pause
  exit /b 1
)

echo Local server started. Test: http://127.0.0.1:9000/
pause
