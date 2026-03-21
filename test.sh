#!/usr/bin/env bash
# test.sh — boot a disk image in QEMU on an Apple M1 (arm64 host)
#
# Usage:
#   ./test.sh arm64          # boot output/arm64/disk.img  (native HVF, fast)
#   ./test.sh amd64          # boot output/amd64/disk.img  (TCG emulation, slow)
#   ./test.sh arm64 path/to/other.img
#   ./test.sh amd64 path/to/other.img
#
# Prerequisites:
#   brew install qemu
#   # For EFI firmware (arm64):
#   brew install qemu   # ships edk2-aarch64-code.fd
#   # For EFI firmware (amd64):
#   brew install ovmf   # or: brew install qemu (ships edk2-x86_64-code.fd)

set -euo pipefail

ARCH="${1:-arm64}"
IMG="${2:-}"

# ── Resolve image path ────────────────────────────────────────────────────────
if [[ -z "${IMG}" ]]; then
  IMG="output/${ARCH}/disk.img"
fi

if [[ ! -f "${IMG}" ]]; then
  echo "Error: disk image not found: ${IMG}"
  echo "Build it first with:"
  echo "  docker buildx bake --allow=security.insecure disk-image-${ARCH}"
  exit 1
fi

# ── Find QEMU EFI firmware ────────────────────────────────────────────────────
# Homebrew puts these in different places depending on version/platform.
find_firmware() {
  local candidates=("$@")
  for f in "${candidates[@]}"; do
    [[ -f "${f}" ]] && echo "${f}" && return
  done
  echo ""
}

# ── Launch ────────────────────────────────────────────────────────────────────
case "${ARCH}" in

  arm64)
    # Native execution via Apple Hypervisor.framework — near bare-metal speed.
    # HVF is the macOS equivalent of KVM; no CPU emulation overhead.
    FIRMWARE=$(find_firmware \
      "$(brew --prefix)/share/qemu/edk2-aarch64-code.fd" \
      "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" \
      "/usr/local/share/qemu/edk2-aarch64-code.fd" \
    )

    if [[ -z "${FIRMWARE}" ]]; then
      echo "Error: aarch64 EFI firmware not found. Try: brew install qemu"
      exit 1
    fi

    echo ">>> Booting arm64 image (HVF accelerated)..."
    echo "    Image:    ${IMG}"
    echo "    Firmware: ${FIRMWARE}"
    echo "    Console:  serial (Ctrl-A X to quit)"
    echo ""

    qemu-system-aarch64 \
      -machine virt,accel=hvf \
      -cpu host \
      -smp 4 \
      -m 2048 \
      -drive "if=pflash,format=raw,file=${FIRMWARE},readonly=on" \
      -drive "if=virtio,format=raw,file=${IMG}" \
      -nographic \
      -serial mon:stdio
    ;;

  amd64)
    # Full x86_64 TCG emulation — no hardware acceleration available on M1.
    # This is slow (roughly 10-20% of native speed) but fully functional.
    # Expect boot to take 1-3 minutes.
    FIRMWARE=$(find_firmware \
      "$(brew --prefix)/share/qemu/edk2-x86_64-code.fd" \
      "/opt/homebrew/share/qemu/edk2-x86_64-code.fd" \
      "/usr/local/share/qemu/edk2-x86_64-code.fd" \
    )

    if [[ -z "${FIRMWARE}" ]]; then
      echo "Error: x86_64 EFI firmware not found. Try: brew install qemu"
      exit 1
    fi

    echo ">>> Booting amd64 image (TCG software emulation — this is slow)..."
    echo "    Image:    ${IMG}"
    echo "    Firmware: ${FIRMWARE}"
    echo "    Console:  serial (Ctrl-A X to quit)"
    echo ""

    qemu-system-x86_64 \
      -machine q35 \
      -cpu qemu64 \
      -smp 2 \
      -m 2048 \
      -drive "if=pflash,format=raw,file=${FIRMWARE},readonly=on" \
      -drive "if=virtio,format=raw,file=${IMG}" \
      -nographic \
      -serial mon:stdio
    ;;

  *)
    echo "Usage: $0 [arm64|amd64] [image-path]"
    exit 1
    ;;
esac