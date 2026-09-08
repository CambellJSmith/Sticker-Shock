#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! python3 -c "from PIL import Image" >/dev/null 2>&1; then
    python3 -m pip install --user -r "$SCRIPT_DIR/requirements.txt"
fi

python3 "$SCRIPT_DIR/sticker_creator.py"
