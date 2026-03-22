package main

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/google/uuid"
)

// grubModules is the list of GRUB modules embedded into the self-contained EFI binary.
var grubModules = []string{
	"part_gpt", "fat", "ext2", "normal", "configfile",
	"search", "search_fs_uuid", "linux", "echo", "reboot", "gzio",
	"all_video", "font", "gfxterm",
}

// buildGRUBEFI runs grub-mkimage to compile a self-contained EFI binary and
// writes it into the FAT32 filesystem at EFI/BOOT/<efiBootFilename>.
// -p /boot/grub tells GRUB where to look for grub.cfg on the EFI partition.
func buildGRUBEFI(efiFS filesystem.FileSystem, grubArch, efiBootFilename string) error {
	fmt.Printf(">>> Building GRUB EFI binary (%s)...\n", grubArch)

	tmpEFI, err := os.CreateTemp("", "grub-*.efi")
	if err != nil {
		return fmt.Errorf("temp file for grub efi: %w", err)
	}
	tmpEFIPath := tmpEFI.Name()
	tmpEFI.Close()
	defer os.Remove(tmpEFIPath)

	args := append([]string{
		"-O", grubArch,
		"-o", tmpEFIPath,
		"-p", "/boot/grub",
		"-d", "/usr/lib/grub/" + grubArch,
	}, grubModules...)
	cmd := exec.Command("grub-mkimage", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("grub-mkimage: %w", err)
	}

	fmt.Println(">>> Writing GRUB EFI binary to FAT32...")
	efiData, err := os.ReadFile(tmpEFIPath)
	if err != nil {
		return fmt.Errorf("read grub efi binary: %w", err)
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

	uuidLower := rootFSUUID.String()
	cfg := fmt.Sprintf(
		"set default=0\nset timeout=5\n\nmenuentry %q {\n"+
			"    search --no-floppy --fs-uuid --set=root %s\n"+
			"    linux  %s root=UUID=%s rootfstype=ext4 ro quiet\n"+
			"    initrd %s\n}\n",
		distro, uuidLower, kernelRel, uuidLower, initrdRel,
	)
	if err := efiFS.Mkdir("/boot"); err != nil {
		return fmt.Errorf("fat32 mkdir /boot: %w", err)
	}
	if err := efiFS.Mkdir("/boot/grub"); err != nil {
		return fmt.Errorf("fat32 mkdir /boot/grub: %w", err)
	}
	return writeTextFile(efiFS, "/boot/grub/grub.cfg", []byte(cfg))
}
