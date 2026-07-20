@echo off
setlocal
cd /d "%~dp0.."

echo Starting public Mock Venue Server and generating a public QR code...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_public_mock_venue.ps1"
set EXIT_CODE=%ERRORLEVEL%
echo.
if not "%EXIT_CODE%"=="0" echo Startup did not complete. See the message above.
pause
exit /b %EXIT_CODE%
