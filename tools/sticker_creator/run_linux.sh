#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Sticker Creator could not find Python: $PYTHON_BIN"
    echo "Install Python or set PYTHON_BIN to the interpreter you want to use."
    exit 1
fi

if ! "$PYTHON_BIN" -c "from PIL import Image; import numpy; from scipy import ndimage" >/dev/null 2>&1; then # Checks the existing interpreter without creating or modifying a Python environment.
    echo "Sticker Creator requires Pillow, NumPy, and SciPy in the selected Python installation."
    echo "Install them into that existing Python environment, then run this launcher again:"
    echo "  $PYTHON_BIN -m pip install -r $SCRIPT_DIR/requirements.txt"
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/sticker_creator_entry.py"
