package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds all configuration derived from environment variables.
type Config struct {
	ImgPath         string
	EFISize         int64
	Distro          string
	RootfsPath      string
	TargetArch      string
	GRUBArch        string
	EFIBootFilename string
}

// loadConfig reads configuration from environment variables, validates the
// target architecture, and parses size strings into bytes.
func loadConfig() (*Config, error) {
	targetArch := getEnv("TARGETARCH", "amd64")

	var grubArch, efiBootFilename string
	switch targetArch {
	case "amd64":
		grubArch = "x86_64-efi"
		efiBootFilename = "BOOTX64.EFI"
	case "arm64":
		grubArch = "arm64-efi"
		efiBootFilename = "BOOTAA64.EFI"
	default:
		return nil, fmt.Errorf("unsupported TARGETARCH: %s", targetArch)
	}

	efiSize, err := parseSize(getEnv("EFI_SIZE", "512M"))
	if err != nil {
		return nil, fmt.Errorf("EFI_SIZE: %w", err)
	}

	return &Config{
		ImgPath:         getEnv("IMG", "/output/disk.img"),
		EFISize:         efiSize,
		Distro:          getEnv("DISTRO", "linux"),
		RootfsPath:      getEnv("ROOTFS", "/rootfs"),
		TargetArch:      targetArch,
		GRUBArch:        grubArch,
		EFIBootFilename: efiBootFilename,
	}, nil
}

// parseSize converts "4G", "512M", "1024K" → bytes.
func parseSize(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("empty size string")
	}
	mult := int64(1)
	switch {
	case strings.HasSuffix(s, "G"):
		mult = 1 << 30
		s = s[:len(s)-1]
	case strings.HasSuffix(s, "M"):
		mult = 1 << 20
		s = s[:len(s)-1]
	case strings.HasSuffix(s, "K"):
		mult = 1 << 10
		s = s[:len(s)-1]
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid size %q: %w", s, err)
	}
	return n * mult, nil
}

// getEnv returns the value of the environment variable named by key, or def if
// the variable is unset or empty.
func getEnv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}
