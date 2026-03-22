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

# ── Resolve arch-specific GRUB EFI target ────────────────────────────────────
case "${TARGETARCH}" in
  amd64) GRUB_EFI_TARGET="x86_64-efi" ;;
  arm64) GRUB_EFI_TARGET="arm64-efi"  ;;
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


# ── Generate grub.cfg ─────────────────────────────────────────────────────────
# Write grub.cfg directly rather than using update-grub: inside the chroot
# grub-probe sees the build-time device (/dev/mapper/loopNpX) and emits that
# as root=, which is meaningless on the target machine. Using the UUID we
# already have guarantees the correct root= on every boot.
echo ">>> Generating grub.cfg..."
# find works for both Debian (vmlinuz-6.x, initrd.img-6.x)
# and Alpine (vmlinuz-lts, initramfs-lts)
KERNEL=$(find "${MNT}/boot" -maxdepth 1 -name 'vmlinuz*' ! -name '*.old' | sort -V | tail -1)
INITRD=$(find "${MNT}/boot" -maxdepth 1 \( -name 'initrd*' -o -name 'initramfs*' \) ! -name '*.old' | sort -V | tail -1)
[ -n "${KERNEL}" ] || { echo "ERROR: no kernel found in ${MNT}/boot"; exit 1; }
[ -n "${INITRD}" ] || { echo "ERROR: no initrd/initramfs found in ${MNT}/boot"; exit 1; }
KERNEL="${KERNEL#"${MNT}"}"   # strip mount prefix → /boot/vmlinuz-…
INITRD="${INITRD#"${MNT}"}"

mkdir -p "${MNT}/boot/grub"
cat > "${MNT}/boot/grub/grub.cfg" <<GRUBCFG
set default=0
set timeout=5

menuentry "Linux" {
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux  ${KERNEL} root=UUID=${ROOT_UUID} rootfstype=ext4 ro quiet
    initrd ${INITRD}
}
GRUBCFG

# ── Shrink image to fit + 10% ─────────────────────────────────────────────────
echo ">>> Shrinking image..."

# Unmount everything before resizing the filesystem
umount "${MNT}/boot/efi" 2>/dev/null || true
umount "${MNT}/dev"      2>/dev/null || true
umount "${MNT}/proc"     2>/dev/null || true
umount "${MNT}/sys"      2>/dev/null || true
umount "${MNT}"          2>/dev/null || true

# Shrink the ext4 filesystem to minimum size, then expand to minimum + 10%
e2fsck -fy "${ROOT}"
MIN_BLOCKS=$(resize2fs -P "${ROOT}" 2>&1 | awk '/Estimated minimum size/ {print $NF}')
BLOCK_SIZE=$(tune2fs -l "${ROOT}" | awk '/^Block size:/ {print $3}')
TARGET_BLOCKS=$(( (MIN_BLOCKS * 11 + 9) / 10 ))   # ceil(min * 1.1)
resize2fs "${ROOT}" "${TARGET_BLOCKS}"

# Shrink partition 2 in the GPT to the new filesystem size
PART2_START=$(sgdisk -i 2 "${LOOP}" | awk '/First sector:/ {print $3}')
TARGET_SECTORS=$(( (TARGET_BLOCKS * BLOCK_SIZE + 511) / 512 ))  # ceil to sector
PART2_END=$(( PART2_START + TARGET_SECTORS - 1 ))
sgdisk --delete=2 "${LOOP}"
sgdisk \
  --new=2:"${PART2_START}":"${PART2_END}" \
  --typecode=2:8300 \
  --change-name=2:"Linux root" \
  "${LOOP}"

# Detach loop/dm devices, truncate image, then relocate backup GPT
kpartx -dv "${LOOP}" 2>/dev/null || true
losetup -d "${LOOP}" 2>/dev/null || true
NEW_SECTORS=$(( PART2_END + 1 + 33 ))   # +33 sectors for backup GPT (32 entries + header)
truncate -s $(( NEW_SECTORS * 512 )) "${IMG}"
sgdisk -e "${IMG}"   # move backup GPT to the new end of disk

# ── Done ──────────────────────────────────────────────────────────────────────
echo ">>> Disk image ready: ${IMG} (${TARGETARCH})"
du -sh "${IMG}"
