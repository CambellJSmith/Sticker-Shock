@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "VENV_DIR=%SCRIPT_DIR%.venv"
set "PYTHON_BIN=%VENV_DIR%\Scripts\python.exe"

if not exist "%PYTHON_BIN%" (
    echo Setting up Sticker Creator local Python environment...
    python -m venv "%VENV_DIR%"
    if errorlevel 1 exit /b 1
)

"%PYTHON_BIN%" -c "from PIL import Image" >nul 2>&1
if errorlevel 1 (
    echo Installing Sticker Creator dependencies into its local environment...
    "%PYTHON_BIN%" -m pip install --upgrade pip
    if errorlevel 1 exit /b 1
    "%PYTHON_BIN%" -m pip install -r "%SCRIPT_DIR%requirements.txt"
    if errorlevel 1 exit /b 1
)

"%PYTHON_BIN%" "%SCRIPT_DIR%sticker_creator_entry.py"
