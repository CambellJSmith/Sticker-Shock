@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if not defined PYTHON_BIN set "PYTHON_BIN=python"

"%PYTHON_BIN%" --version >nul 2>&1
if errorlevel 1 (
    echo Sticker Creator could not find Python: %PYTHON_BIN%
    echo Install Python or set PYTHON_BIN to the interpreter you want to use.
    exit /b 1
)

"%PYTHON_BIN%" -c "from PIL import Image; import numpy; from scipy import ndimage" >nul 2>&1
if errorlevel 1 (
    echo Sticker Creator requires Pillow, NumPy, and SciPy in the selected Python installation.
    echo Install them into that existing Python environment, then run this launcher again:
    echo   "%PYTHON_BIN%" -m pip install -r "%SCRIPT_DIR%requirements.txt"
    exit /b 1
)

"%PYTHON_BIN%" "%SCRIPT_DIR%sticker_creator_entry.py"
