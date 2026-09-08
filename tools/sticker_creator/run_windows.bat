@echo off
set SCRIPT_DIR=%~dp0
python -c "from PIL import Image" >nul 2>&1
if errorlevel 1 python -m pip install --user -r "%SCRIPT_DIR%requirements.txt"
python "%SCRIPT_DIR%sticker_creator.py"
