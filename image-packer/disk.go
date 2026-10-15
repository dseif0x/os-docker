package main

const (
	sectorSize    = 512
	efiStart      = uint64(2048) // first usable LBA (1 MiB alignment)
	backupGPTSecs = uint64(33)   // sectors reserved at end for backup GPT
)

// roundUpMiB rounds n up to the nearest MiB boundary.
func roundUpMiB(n int64) int64 {
	const mib = 1 << 20
	return ((n + mib - 1) / mib) * mib
}
