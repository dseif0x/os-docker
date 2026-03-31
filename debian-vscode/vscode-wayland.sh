#!/bin/bash
set -euo pipefail

KEEPALIVE_FILE=/tmp/keepalive.txt
touch "$KEEPALIVE_FILE"

CODE_CMD="/usr/bin/code --no-sandbox --disable-gpu --user-data-dir=\$HOME/.code --wait '$KEEPALIVE_FILE'"

# Try hardware acceleration first
echo "[INFO] Attempting hardware accelerated launch..."
set +e
WLR_RENDERER=gles2 cage -s -- /bin/sh -lc "$CODE_CMD"
CAGE_EXIT=$?
set -e

if [ $CAGE_EXIT -eq 0 ]; then
    # Clean exit - user closed VS Code
    exit 0
fi

echo "[WARN] Hardware accelerated launch failed (exit $CAGE_EXIT), falling back to software rendering..."

export WLR_RENDERER=pixman
export WLR_RENDERER_ALLOW_SOFTWARE=1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe

exec cage -s -- /bin/sh -lc "$CODE_CMD"