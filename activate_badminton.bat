@echo off
setlocal
title Good-Badminton Conda Shell

set "PROJECT_DIR=D:\py\Good-Badminton"
set "CONDA_ACTIVATE=C:\Users\jiale\miniconda3\Scripts\activate.bat"

if not exist "%CONDA_ACTIVATE%" (
    echo [ERROR] Conda activation script was not found:
    echo %CONDA_ACTIVATE%
    pause
    exit /b 1
)

cd /d "%PROJECT_DIR%"
call "%CONDA_ACTIVATE%" badminton

echo.
echo Good-Badminton environment is active.
echo Project: %PROJECT_DIR%
echo Python:
python --version
echo.
cmd /k
