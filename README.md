# os-docker

Builds bootable Linux VM disk images from Docker. Supports Alpine and Debian, for both `amd64` and `arm64`.

## How it works

1. A distro-specific Dockerfile builds a root filesystem (kernel + userspace) inside a Docker image.
2. `Dockerfile.disk-image` runs `build-image.sh` with elevated privileges to create a GPT disk image with an EFI System Partition (FAT32, GRUB) and a root partition (ext4, rootfs). The image is shrunk to fit its contents.
3. The final disk image is exported from the container to `output/<distro>/`.

## Prerequisites

```bash
brew install qemu docker
```

Docker must support BuildKit with the `security.insecure` entitlement (required for loopback device operations inside the build container).

## Building

Build all distros for all architectures:

```bash
docker buildx bake --allow=security.insecure
```

Build a specific distro:

```bash
docker buildx bake disk-image-alpine --allow=security.insecure
docker buildx bake disk-image-debian --allow=security.insecure
```

Output images land in `output/alpine/` and `output/debian/`, one per architecture (`linux_amd64/disk.img`, `linux_arm64/disk.img`).

## Testing

Default credentials: `root` / `root`

### arm64 (Apple Silicon — native speed)

```bash
qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu host \
  -smp 4 \
  -m 2048 \
  -drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,readonly=on" \
  -drive "if=virtio,format=raw,file=output/alpine/linux_arm64/disk.img" \
  -nographic \
  -serial mon:stdio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

To add a display (for debian-vscode for example):
```bash
qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu host \
  -smp 4 \
  -m 2048 \
  -serial stdio \
  -machine virt \
  -drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,readonly=on" \
  -drive "if=virtio,format=raw,file=disk.img" \
  -device virtio-gpu \
  -display default \
  -device usb-ehci \
  -device usb-kbd \
  -device usb-mouse
```

### amd64 (software emulation on Apple Silicon — slow)

```bash
qemu-system-x86_64 \
  -machine q35 \
  -cpu qemu64 \
  -smp 2 \
  -m 2048 \
  -drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-x86_64-code.fd,readonly=on" \
  -drive "if=virtio,format=raw,file=output/debian/linux_amd64/disk.img" \
  -nographic \
  -serial mon:stdio
```

## Disk layout

| Partition | Size     | Type  | Contents        |
|-----------|----------|-------|-----------------|
| 1         | 64 MiB  | FAT32 | EFI + GRUB      |
| 2         | variable | ext4  | root filesystem |

EFI partition is 64MiB by default but can be changed: `docker buildx bake disk-image-alpine --allow=security.insecure --set "*.args.EFI_SIZE=100M"`.

The root partition is shrunk to the minimum size that fits the content, plus 10% headroom.
