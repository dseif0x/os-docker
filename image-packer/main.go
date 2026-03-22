// image-packer — runs inside the packager container.
// Produces /output/disk.img: a bootable GPT disk with:
//
// partition 1 — EFI System Partition (FAT32)
//
//	└── EFI/BOOT/BOOT{X64,AA64}.EFI  (GRUB EFI binary)
//	└── boot/grub/grub.cfg
//
// partition 2 — Linux root (ext4, full rootfs)
//
// Uses github.com/diskfs/go-diskfs for all disk/filesystem operations.
// The only external tool invoked is grub-mkimage to produce the EFI binary.
//
// Environment variables:
//
// TARGETARCH — amd64 | arm64 (set by BuildKit / bake)
// EFI_SIZE   — e.g. 64M (default 512M)
// DISTRO     — label used in grub.cfg menuentry (default: linux)
// IMG        — output path (default: /output/disk.img)
// ROOTFS     — source rootfs directory (default: /rootfs)
package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/filesystem/ext4"
	"github.com/diskfs/go-diskfs/filesystem/fat32"
	"github.com/diskfs/go-diskfs/partition/gpt"
	"github.com/google/uuid"
)

func buildDiskImage() error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	// ── Find kernel + initrd ─────────────────────────────────────────────────
	fmt.Println(">>> Finding kernel and initrd...")
	bootSrc := filepath.Join(cfg.RootfsPath, "boot")
	kernel := findLatest(bootSrc, "vmlinuz*")
	if kernel == "" {
		return fmt.Errorf("no kernel found in %s", bootSrc)
	}
	initrd := findLatest(bootSrc, "initrd*", "initramfs*")
	if initrd == "" {
		return fmt.Errorf("no initrd/initramfs found in %s", bootSrc)
	}
	kernelRel := filepath.ToSlash(strings.TrimPrefix(kernel, cfg.RootfsPath))
	initrdRel := filepath.ToSlash(strings.TrimPrefix(initrd, cfg.RootfsPath))
	fmt.Printf("    kernel: %s\n    initrd: %s\n", kernelRel, initrdRel)

	// ── Compute rootfs size ──────────────────────────────────────────────────
	fmt.Println(">>> Measuring rootfs...")
	skipDirs := map[string]bool{"proc": true, "sys": true, "dev": true, "run": true}
	dataBytes, fileCount, err := rootfsStats(cfg.RootfsPath, skipDirs)
	if err != nil {
		return fmt.Errorf("measure rootfs: %w", err)
	}
	fmt.Printf("    data: %.1f MiB  files: %d\n", float64(dataBytes)/(1<<20), fileCount)

	// Add 25% metadata headroom + 64 MiB minimum margin, aligned to 1 MiB.
	rootPartSize := roundUpMiB(maxInt64(int64(float64(dataBytes)*1.25), dataBytes+64*(1<<20)))
	fmt.Printf("    ext4 partition: %.1f MiB\n", float64(rootPartSize)/(1<<20))

	// ── GPT sector layout ────────────────────────────────────────────────────
	efiSectors := uint64(cfg.EFISize / sectorSize)
	efiEnd := efiStart + efiSectors - 1
	rootStartSec := efiEnd + 1
	rootSectors := uint64(rootPartSize / sectorSize)
	rootEndSec := rootStartSec + rootSectors - 1
	totalSectors := rootEndSec + 1 + backupGPTSecs
	totalSize := int64(totalSectors) * sectorSize

	fmt.Printf(">>> Building disk image for %s (%.1f MiB total)\n",
		cfg.TargetArch, float64(totalSize)/(1<<20))

	// ── Pre-generate filesystem / partition identifiers ──────────────────────
	rootFSUUID, err := uuid.NewRandom()
	if err != nil {
		return fmt.Errorf("generate root UUID: %w", err)
	}
	efiPartGUID, err := uuid.NewRandom()
	if err != nil {
		return fmt.Errorf("generate EFI PARTUUID: %w", err)
	}

	// ── Create disk image + GPT ──────────────────────────────────────────────
	fmt.Println(">>> Creating disk image and GPT partition table...")
	if err := os.MkdirAll(filepath.Dir(cfg.ImgPath), 0o755); err != nil {
		return fmt.Errorf("mkdir output dir: %w", err)
	}
	d, err := diskfs.Create(cfg.ImgPath, totalSize, diskfs.SectorSize512)
	if err != nil {
		return fmt.Errorf("create disk image: %w", err)
	}
	defer func() { _ = d.Close() }()

	if err := d.Partition(&gpt.Table{
		ProtectiveMBR: true,
		Partitions: []*gpt.Partition{
			{
				Start: efiStart,
				End:   efiEnd,
				Type:  gpt.EFISystemPartition,
				Name:  "EFI System",
				GUID:  strings.ToUpper(efiPartGUID.String()),
				Index: 1,
			},
			{
				Start: rootStartSec,
				End:   rootEndSec,
				Type:  gpt.LinuxFilesystem,
				Name:  "Linux root",
				Index: 2,
			},
		},
	}); err != nil {
		return fmt.Errorf("write partition table: %w", err)
	}

	// ── Create filesystems ────────────────────────────────────────────────────
	fmt.Println(">>> Creating FAT32 filesystem on EFI partition...")
	efiFS, err := fat32.Create(d.Backend, int64(efiSectors)*sectorSize,
		int64(efiStart)*sectorSize, d.LogicalBlocksize, "EFI", false)
	if err != nil {
		return fmt.Errorf("create FAT32: %w", err)
	}

	fmt.Println(">>> Creating ext4 filesystem on root partition...")
	rootFS, err := ext4.Create(d.Backend, int64(rootSectors)*sectorSize,
		int64(rootStartSec)*sectorSize, d.LogicalBlocksize,
		&ext4.Params{
			UUID:            &rootFSUUID,
			VolumeName:      "root",
			InodeRatio:      4096, // more inodes for distros with many small files
			SectorsPerBlock: 8,   // 4 KiB blocks — standard ext4 size; avoids multi-level extent tree bug in go-diskfs for large files
		},
	)
	if err != nil {
		return fmt.Errorf("create ext4: %w", err)
	}

	// ── Populate root filesystem ──────────────────────────────────────────────
	fmt.Println(">>> Copying rootfs into ext4...")
	if err := copyRootfsToExt4(cfg.RootfsPath, rootFS, skipDirs); err != nil {
		return fmt.Errorf("copy rootfs: %w", err)
	}

	// Ensure virtual-fs stub dirs exist (excluded from source copy).
	for _, dir := range []string{"proc", "sys", "dev", "run"} {
		_ = rootFS.Mkdir(dir)
		_ = rootFS.Chmod(dir, 0o755)
	}

	// ── Write /etc/fstab ─────────────────────────────────────────────────────
	fmt.Println(">>> Writing /etc/fstab...")
	fstab := fmt.Sprintf(
		"# <file system>                           <mount point>  <type>  <options>           <dump>  <pass>\n"+
			"UUID=%-36s  /              ext4    errors=remount-ro   0       1\n"+
			"PARTUUID=%-32s  /boot/efi      vfat    umask=0077,nofail   0       2\n",
		rootFSUUID.String(),
		efiPartGUID.String(),
	)
	if err := writeTextFile(rootFS, "/etc/fstab", []byte(fstab)); err != nil {
		return fmt.Errorf("write fstab: %w", err)
	}

	// ── Build GRUB EFI binary + grub.cfg ─────────────────────────────────────
	if err := buildGRUBEFI(efiFS, cfg.GRUBArch, cfg.EFIBootFilename); err != nil {
		return err
	}
	if err := writeGRUBConfig(efiFS, cfg.Distro, kernelRel, initrdRel, rootFSUUID); err != nil {
		return err
	}

	// ── Done ─────────────────────────────────────────────────────────────────
	fmt.Printf(">>> Disk image ready: %s (%s)\n", cfg.ImgPath, cfg.TargetArch)
	if info, statErr := os.Stat(cfg.ImgPath); statErr == nil {
		fmt.Printf("    %.1f MiB\n", float64(info.Size())/(1<<20))
	}
	return nil
}

func main() {
	if err := buildDiskImage(); err != nil {
		log.Fatalf("ERROR: %v", err)
	}
}
