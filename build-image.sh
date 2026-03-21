#!/usr/bin/env bash
# build-image.sh — runs inside the packager container (needs security.insecure)
# Produces /output/disk.img: a bootable GPT disk with:
#   partition 1 — 512 MiB EFI System Partition  (FAT32, GRUB EFI)
#   partition 2 — remainder    Linux root         (ext4, rootfs)
#
# Respects:
#   TARGETARCH  — amd64 | arm64  (set by BuildKit / bake, drives GRUB target)
#   IMG_SIZE    — e.g. 4G (default), 8G, etc.
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
IMG=/output/disk.img
IMG_SIZE=${IMG_SIZE:-4G}
ROOTFS=/rootfs
MNT=/mnt/disk
TARGETARCH=${TARGETARCH:-amd64}

# ── Resolve arch-specific GRUB targets ───────────────────────────────────────
case "${TARGETARCH}" in
  amd64)
    GRUB_EFI_TARGET="x86_64-efi"
    GRUB_BIOS_TARGET="i386-pc"
    INSTALL_BIOS=true
    ;;
  arm64)
    GRUB_EFI_TARGET="arm64-efi"
    # arm64 has no BIOS/legacy boot — EFI only
    GRUB_BIOS_TARGET=""
    INSTALL_BIOS=false
    ;;
  *)
    echo "Unsupported TARGETARCH: ${TARGETARCH}"
    exit 1
    ;;
esac

echo ">>> Building disk image for ${TARGETARCH} (GRUB EFI target: ${GRUB_EFI_TARGET})"

# ── Create sparse image ───────────────────────────────────────────────────────
echo ">>> Creating ${IMG_SIZE} disk image..."
truncate -s "${IMG_SIZE}" "${IMG}"

# ── Partition (GPT: ESP + root) ───────────────────────────────────────────────
echo ">>> Partitioning..."
sgdisk --zap-all "${IMG}"
sgdisk \
  --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI System" \
  --new=2:0:0     --typecode=2:8300 --change-name=2:"Linux root" \
  "${IMG}"

# ── Attach loop device ────────────────────────────────────────────────────────
echo ">>> Setting up loop device..."
LOOP=$(losetup --find --show "${IMG}")
# In containers udev is not running, so kernel partition nodes (/dev/loopNpX)
# never appear. kpartx creates device-mapper nodes (/dev/mapper/loopNpX) that
# work reliably without udev.
kpartx -av "${LOOP}"
LOOPNAME=$(basename "${LOOP}")   # e.g. loop2
ESP="/dev/mapper/${LOOPNAME}p1"
ROOT="/dev/mapper/${LOOPNAME}p2"

cleanup() {
  echo ">>> Cleanup..."
  umount "${MNT}/boot/efi" 2>/dev/null || true
  umount "${MNT}/dev"      2>/dev/null || true
  umount "${MNT}/proc"     2>/dev/null || true
  umount "${MNT}/sys"      2>/dev/null || true
  umount "${MNT}"          2>/dev/null || true
  kpartx -dv "${LOOP}"     2>/dev/null || true
  losetup -d "${LOOP}"     2>/dev/null || true
}
trap cleanup EXIT

# ── Format ────────────────────────────────────────────────────────────────────
echo ">>> Formatting partitions..."
mkfs.fat -F32 -n EFI "${ESP}"
mkfs.ext4 -L root "${ROOT}"

# ── Mount ─────────────────────────────────────────────────────────────────────
echo ">>> Mounting..."
mkdir -p "${MNT}"
mount "${ROOT}" "${MNT}"
mkdir -p "${MNT}/boot/efi"
mount "${ESP}" "${MNT}/boot/efi"

# ── Copy rootfs ───────────────────────────────────────────────────────────────
echo ">>> Copying rootfs..."
rsync -aHAX \
  --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
  "${ROOTFS}/" "${MNT}/"

# ── Bind-mount virtual filesystems for chroot ─────────────────────────────────
# rsync excluded these dirs, so ensure they exist before mounting.
mkdir -p "${MNT}/proc" "${MNT}/sys" "${MNT}/dev" "${MNT}/run"
mount --bind /proc "${MNT}/proc"
mount --bind /sys  "${MNT}/sys"
mount --bind /dev  "${MNT}/dev"

# ── Write /etc/fstab ─────────────────────────────────────────────────────────
ROOT_UUID=$(blkid -s UUID -o value "${ROOT}")
ESP_UUID=$(blkid  -s UUID -o value "${ESP}")

cat > "${MNT}/etc/fstab" <<FSTAB
# <file system>                           <mount point> <type>  <options>          <dump> <pass>
UUID=${ROOT_UUID}  /             ext4    errors=remount-ro  0      1
UUID=${ESP_UUID}   /boot/efi     vfat    umask=0077         0      2
FSTAB

# ── Install GRUB ─────────────────────────────────────────────────────────────
# Run grub-install from the packager (not chroot) so it can find its modules
# under /usr/lib/grub/. Point it at the mounted rootfs via --boot-directory
# and --efi-directory.
echo ">>> Installing GRUB EFI (${GRUB_EFI_TARGET})..."
grub-install \
  --target="${GRUB_EFI_TARGET}" \
  --efi-directory="${MNT}/boot/efi" \
  --boot-directory="${MNT}/boot" \
  --bootloader-id=debian \
  --no-nvram \
  --removable

if [[ "${INSTALL_BIOS}" == "true" ]]; then
  echo ">>> Installing GRUB BIOS (${GRUB_BIOS_TARGET})..."
  grub-install \
    --target="${GRUB_BIOS_TARGET}" \
    --boot-directory="${MNT}/boot" \
    "${LOOP}"
fi

# ── Generate grub.cfg ─────────────────────────────────────────────────────────
# update-grub needs the chroot environment to find kernels and generate paths.
echo ">>> Generating grub.cfg..."
chroot "${MNT}" update-grub

# ── Done ──────────────────────────────────────────────────────────────────────
echo ">>> Disk image ready: ${IMG} (${TARGETARCH})"
du -sh "${IMG}"
