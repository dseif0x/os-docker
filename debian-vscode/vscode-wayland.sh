#!/bin/bash
set -euo pipefail

# Detect hardware acceleration
# Simple check: does Vulkan see a device?
if command -v vulkaninfo >/dev/null && vulkaninfo 2>/dev/null | grep -q "GPU id"; then
    echo "[INFO] Vulkan device detected, enabling hardware acceleration."
    unset GALLIUM_DRIVER
    unset MESA_LOADER_DRIVER_OVERRIDE
    unset LIBGL_ALWAYS_SOFTWARE
    export WLR_RENDERER=gles2    # wlroots default for GPU
    unset WLR_RENDERER_ALLOW_SOFTWARE
else
    echo "[INFO] No Vulkan device found, falling back to software rendering."
    export WLR_RENDERER=pixman
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
fi

# Keep Cage alive by making Code wait on a dummy file
KEEPALIVE_FILE=/tmp/keepalive.txt
touch "$KEEPALIVE_FILE"

exec cage -s -- /bin/sh -lc "/usr/bin/code --no-sandbox --disable-gpu --user-data-dir=$HOME/.code --wait '$KEEPALIVE_FILE'"
