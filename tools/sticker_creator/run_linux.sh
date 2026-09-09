#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "Setting up Sticker Creator local Python environment..."
    python3 -m venv "$VENV_DIR"
fi

if ! "$PYTHON_BIN" -c "from PIL import Image" >/dev/null 2>&1; then
    echo "Installing Sticker Creator dependencies into its local environment..."
    "$PYTHON_BIN" -m pip install --upgrade pip
    "$PYTHON_BIN" -m pip install -r "$SCRIPT_DIR/requirements.txt"
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/sticker_creator_entry.py"
