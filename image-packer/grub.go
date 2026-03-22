package main

import (
	_ "embed"
	"fmt"

	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/google/uuid"
)

// EFI binaries are pre-built by grub-mkimage in the Docker builder stage and
// embedded here, so the packager container needs no tools at runtime.
//
//go:embed efi/bootx64.efi
var grubEFIx64 []byte

//go:embed efi/bootaa64.efi
var grubEFIaa64 []byte

// buildGRUBEFI writes the pre-built GRUB EFI binary for grubArch into the
// FAT32 filesystem at EFI/BOOT/<efiBootFilename>.
func buildGRUBEFI(efiFS filesystem.FileSystem, grubArch, efiBootFilename string) error {
	fmt.Printf(">>> Writing GRUB EFI binary (%s)...\n", grubArch)

	var efiData []byte
	switch grubArch {
	case "x86_64-efi":
		efiData = grubEFIx64
	case "arm64-efi":
		efiData = grubEFIaa64
	default:
		return fmt.Errorf("no embedded EFI binary for arch %q", grubArch)
	}
	if err := efiFS.Mkdir("/EFI"); err != nil {
		return fmt.Errorf("fat32 mkdir /EFI: %w", err)
	}
	if err := efiFS.Mkdir("/EFI/BOOT"); err != nil {
		return fmt.Errorf("fat32 mkdir /EFI/BOOT: %w", err)
	}
	return writeTextFile(efiFS, "/EFI/BOOT/"+efiBootFilename, efiData)
}

// writeGRUBConfig generates and writes /boot/grub/grub.cfg to the FAT32
// filesystem. GRUB loads this from the EFI partition at boot time.
func writeGRUBConfig(efiFS filesystem.FileSystem, distro, kernelRel, initrdRel string, rootFSUUID uuid.UUID) error {
	fmt.Println(">>> Writing grub.cfg to FAT32...")

	uuidStr := rootFSUUID.String()
	cfg := fmt.Sprintf(
		"set default=0\nset timeout=0\n\nmenuentry %q {\n"+
			"    search --no-floppy --fs-uuid --set=root %s\n"+
			"    linux  %s root=UUID=%s rootfstype=ext4 ro quiet\n"+
			"    initrd %s\n}\n",
		distro, uuidStr, kernelRel, uuidStr, initrdRel,
	)
	if err := efiFS.Mkdir("/boot"); err != nil {
		return fmt.Errorf("fat32 mkdir /boot: %w", err)
	}
	if err := efiFS.Mkdir("/boot/grub"); err != nil {
		return fmt.Errorf("fat32 mkdir /boot/grub: %w", err)
	}
	return writeTextFile(efiFS, "/boot/grub/grub.cfg", []byte(cfg))
}
