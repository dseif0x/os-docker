# os-docker

Builds bootable UEFI disk images for Linux VMs using nothing but Docker. Each
distro is an ordinary Dockerfile; a small Go tool packs the resulting root
filesystem into a GPT disk image with GRUB. Supports `amd64` and `arm64`.

| Distro          | Base                   | Init    | Notes                                              |
|-----------------|------------------------|---------|----------------------------------------------------|
| `alpine`        | `alpine:3.21`          | OpenRC  | Minimal, DHCP on `eth0`, serial getty              |
| `debian`        | `debian:bookworm-slim` | systemd | DHCP via `systemd-networkd`, getty on `tty1`       |
| `debian-vscode` | `debian:bookworm-slim` | systemd | Boots straight into VS Code under Cage (Wayland)   |

Default credentials: `root` / `root` (`debian-vscode` also has `kiosk` / `kiosk`).

## How it works

1. `<distro>/Dockerfile` builds a complete root filesystem (kernel, init
   system, userspace) as a normal Docker image. Each directory is
   self-contained.
2. `Dockerfile.disk-image` compiles [`image-packer`](image-packer/) and runs it
   against that rootfs. The packer uses [go-diskfs](https://github.com/diskfs/go-diskfs)
   to create the GPT table, a FAT32 EFI System Partition and an ext4 root
   partition entirely in userspace, so no privileged build steps, loop devices
   or mounts are needed. GRUB EFI binaries are built with `grub-mkimage` in
   per-arch stages and embedded into the packer.
3. The finished `disk.img` is exported to `output/<distro>/`.

`docker-bake.hcl` is distro-agnostic: it turns every name in its `DISTROS`
list into a `rootfs-<distro>` target and a `disk-image-<distro>` target that
consumes it. Adding a distro means creating a directory with a Dockerfile and
appending its name to that list.

## Prerequisites

Docker with BuildKit (Docker Desktop is fine). Building the non-native
architecture uses QEMU user emulation, which Docker Desktop ships with.

For booting images locally:

```bash
brew install qemu
```

## Building

```bash
docker buildx bake                                                 # all distros, both archs
docker buildx bake disk-image-alpine                               # one distro, both archs
docker buildx bake disk-image-debian --set "*.platform=linux/arm64" # one distro, one arch
```

Output layout:

- single platform: `output/<distro>/disk.img`
- multiple platforms: `output/<distro>/linux_amd64/disk.img` and `output/<distro>/linux_arm64/disk.img`

The EFI partition size defaults to 64 MiB and can be overridden:

```bash
EFI_SIZE=128M docker buildx bake disk-image-alpine
```

## Testing

`test.sh` boots an image in QEMU with the right firmware, accelerator and
console settings for the host:

```bash
./test.sh alpine                 # native arch (HVF on Apple Silicon)
./test.sh debian amd64           # cross-arch via TCG emulation, slow
./test.sh debian-vscode --gui    # opens a window with virtio GPU + USB input
```

Run `./test.sh --help` for all options. Press `Ctrl-A X` to quit QEMU.

## Disk layout

| Partition | Size                          | Type  | Contents                                |
|-----------|-------------------------------|-------|-----------------------------------------|
| 1         | `EFI_SIZE` (64 MiB)           | FAT32 | `EFI/BOOT/BOOT{X64,AA64}.EFI`, `boot/grub/grub.cfg` |
| 2         | rootfs + 25% (min. 64 MiB free) | ext4  | root filesystem                         |

GRUB is installed to the removable-media path so firmware boots it without
NVRAM entries. `grub.cfg` and `/etc/fstab` reference the filesystems by UUID,
so the image boots the same from any disk controller.

## CI

`.github/workflows/build.yml` expands the bake matrix and builds every
distro/arch pair on a native runner, uploading each `disk.img` as an artifact.
