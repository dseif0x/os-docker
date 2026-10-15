#!/usr/bin/env bash
# test.sh — boot a built disk image in QEMU.
#
# Usage:
#   ./test.sh <distro> [arch] [--gui]
#
#   distro   alpine | debian | debian-vscode   (any directory under output/)
#   arch     arm64 | amd64                     (default: host architecture)
#   --gui    attach a virtio GPU + USB keyboard/mouse window (debian-vscode)
#
# Examples:
#   ./test.sh alpine                 # output/alpine/{linux_arm64/,}disk.img
#   ./test.sh debian amd64           # x86_64 under TCG emulation (slow)
#   ./test.sh debian-vscode --gui
#   IMG=path/to/disk.img ./test.sh alpine arm64
#
# Environment overrides: IMG (image path), MEM (MiB, default 2048), CPUS (default 4).
# The serial console is on this terminal; press Ctrl-A X to quit QEMU.

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

DISTRO=""
ARCH=""
GUI=0
for arg in "$@"; do
  case "${arg}" in
    --gui|-g)       GUI=1 ;;
    -h|--help)      usage 0 ;;
    arm64|amd64)    ARCH="${arg}" ;;
    -*)             echo "Unknown option: ${arg}" >&2; usage ;;
    *)              [[ -z "${DISTRO}" ]] && DISTRO="${arg}" || { echo "Unexpected argument: ${arg}" >&2; usage; } ;;
  esac
done
[[ -n "${DISTRO}" ]] || usage

HOST_OS=$(uname -s)
case "$(uname -m)" in
  arm64|aarch64) HOST_ARCH=arm64 ;;
  x86_64)        HOST_ARCH=amd64 ;;
  *)             HOST_ARCH="" ;;
esac
ARCH="${ARCH:-${HOST_ARCH:-arm64}}"
MEM="${MEM:-2048}"
CPUS="${CPUS:-4}"

# ── Locate the disk image ─────────────────────────────────────────────────────
# bake writes output/<distro>/disk.img for a single-platform build and
# output/<distro>/linux_<arch>/disk.img when building several platforms at once.
if [[ -z "${IMG:-}" ]]; then
  for candidate in "output/${DISTRO}/linux_${ARCH}/disk.img" "output/${DISTRO}/disk.img"; do
    [[ -f "${candidate}" ]] && IMG="${candidate}" && break
  done
fi
if [[ -z "${IMG:-}" || ! -f "${IMG}" ]]; then
  echo "Error: no disk image for ${DISTRO}/${ARCH} under output/. Build it with:" >&2
  echo "  docker buildx bake disk-image-${DISTRO} --set '*.platform=linux/${ARCH}'" >&2
  exit 1
fi

# ── Locate EDK2 firmware ──────────────────────────────────────────────────────
case "${ARCH}" in
  arm64) QEMU=qemu-system-aarch64; FW_NAME=edk2-aarch64-code.fd ;;
  amd64) QEMU=qemu-system-x86_64;  FW_NAME=edk2-x86_64-code.fd  ;;
esac
FW_DIRS=(/opt/homebrew/share/qemu /usr/local/share/qemu /usr/share/qemu /usr/share/edk2/aarch64 /usr/share/OVMF)
command -v brew >/dev/null 2>&1 && FW_DIRS=("$(brew --prefix)/share/qemu" "${FW_DIRS[@]}")
FIRMWARE=""
for dir in "${FW_DIRS[@]}"; do
  [[ -f "${dir}/${FW_NAME}" ]] && FIRMWARE="${dir}/${FW_NAME}" && break
done
if [[ -z "${FIRMWARE}" ]]; then
  echo "Error: ${FW_NAME} not found (looked in: ${FW_DIRS[*]}). Try: brew install qemu" >&2
  exit 1
fi

# ── Pick an accelerator ───────────────────────────────────────────────────────
# Native arch gets hardware virtualisation (HVF on macOS, KVM on Linux);
# anything else falls back to TCG software emulation, which is slow.
ACCEL=tcg
if [[ "${ARCH}" == "${HOST_ARCH}" ]]; then
  case "${HOST_OS}" in
    Darwin) ACCEL=hvf ;;
    Linux)  [[ -w /dev/kvm ]] && ACCEL=kvm ;;
  esac
fi

# ── Assemble the QEMU command line ────────────────────────────────────────────
case "${ARCH}" in
  arm64) MACHINE_ARGS=(-machine "virt,accel=${ACCEL}" -cpu "$([[ ${ACCEL} == tcg ]] && echo max || echo host)"); GPU=virtio-gpu-pci ;;
  amd64) MACHINE_ARGS=(-machine "q35,accel=${ACCEL}"  -cpu "$([[ ${ACCEL} == tcg ]] && echo qemu64 || echo host)"); GPU=virtio-vga ;;
esac

ARGS=(
  "${MACHINE_ARGS[@]}"
  -smp "${CPUS}"
  -m "${MEM}"
  -drive "if=pflash,format=raw,file=${FIRMWARE},readonly=on"
  -drive "if=virtio,format=raw,file=${IMG}"
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0
  -serial mon:stdio
)
if (( GUI )); then
  ARGS+=(-display default -device "${GPU}" -device qemu-xhci -device usb-kbd -device usb-tablet)
else
  ARGS+=(-nographic)
fi

echo ">>> Booting ${DISTRO} (${ARCH}, accel=${ACCEL}$( (( GUI )) && echo ", gui"))"
echo "    Image:    ${IMG}"
echo "    Firmware: ${FIRMWARE}"
echo "    Console:  serial on this terminal (Ctrl-A X to quit)"
echo
exec "${QEMU}" "${ARGS[@]}"
