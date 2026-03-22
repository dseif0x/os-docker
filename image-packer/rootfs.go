package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"

	"github.com/diskfs/go-diskfs/filesystem"
)

// findLatest returns the lexicographically last file in dir matching any glob
// pattern, excluding ".old" suffixes.
func findLatest(dir string, patterns ...string) string {
	var matches []string
	for _, p := range patterns {
		ms, _ := filepath.Glob(filepath.Join(dir, p))
		for _, m := range ms {
			if !strings.HasSuffix(m, ".old") {
				matches = append(matches, m)
			}
		}
	}
	if len(matches) == 0 {
		return ""
	}
	sort.Strings(matches)
	return matches[len(matches)-1]
}

// rootfsStats returns the total data bytes and file count under dir,
// skipping the given top-level subdirectories.
func rootfsStats(dir string, skipDirs map[string]bool) (dataBytes int64, fileCount int64, err error) {
	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() && filepath.Dir(path) == dir && skipDirs[d.Name()] {
			return filepath.SkipDir
		}
		if !d.IsDir() {
			info, e := d.Info()
			if e == nil {
				dataBytes += info.Size()
			}
			fileCount++
		}
		return nil
	})
	return
}

// copyRootfsToExt4 walks srcDir and writes every entry to dstFS (an ext4
// filesystem), excluding the named top-level subdirectories.
// Hardlinks are handled by copying file content for each link.
// Named pipes, sockets and device nodes are silently skipped.
func copyRootfsToExt4(srcDir string, dstFS filesystem.FileSystem, skipDirs map[string]bool) error {
	// seenInodes tracks already-copied hardlink groups: srcIno → dstPath.
	seenInodes := map[uint64]string{}

	return filepath.WalkDir(srcDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && filepath.Dir(path) == srcDir && skipDirs[d.Name()] {
			return filepath.SkipDir
		}

		rel := strings.TrimPrefix(filepath.ToSlash(strings.TrimPrefix(path, srcDir)), "/")
		if rel == "" {
			return nil // root dir already exists in ext4
		}
		info, err := os.Lstat(path)
		if err != nil {
			return fmt.Errorf("lstat %s: %w", path, err)
		}
		st, ok := info.Sys().(*syscall.Stat_t)
		if !ok {
			return fmt.Errorf("unexpected stat type for %s", path)
		}
		mode := info.Mode()

		switch {
		case mode.IsDir():
			if err := dstFS.Mkdir(rel); err != nil {
				return fmt.Errorf("mkdir %s: %w", rel, err)
			}
			if err := dstFS.Chmod(rel, mode); err != nil && !errors.Is(err, filesystem.ErrNotImplemented) {
				return fmt.Errorf("chmod %s: %w", rel, err)
			}
			if err := dstFS.Chown(rel, int(st.Uid), int(st.Gid)); err != nil && !errors.Is(err, filesystem.ErrNotImplemented) {
				return fmt.Errorf("chown %s: %w", rel, err)
			}

		case mode&os.ModeSymlink != 0:
			target, err := os.Readlink(path)
			if err != nil {
				return fmt.Errorf("readlink %s: %w", path, err)
			}
			if err := dstFS.Symlink(target, rel); err != nil && !errors.Is(err, filesystem.ErrNotImplemented) {
				return fmt.Errorf("symlink %s→%s: %w", rel, target, err)
			}

		case mode.IsRegular():
			// Handle hardlinks: if we've seen this inode, try a hard link.
			// If Link is not implemented, fall through to a full copy.
			if st.Nlink > 1 {
				if prev, seen := seenInodes[st.Ino]; seen {
					linkErr := dstFS.Link(prev, rel)
					if linkErr == nil {
						return nil
					}
					if !errors.Is(linkErr, filesystem.ErrNotImplemented) {
						return fmt.Errorf("link %s→%s: %w", prev, rel, linkErr)
					}
					// ErrNotImplemented: fall through to copy.
				} else {
					seenInodes[st.Ino] = rel
				}
			}
			if err := copyRegularFile(path, rel, dstFS, mode, st); err != nil {
				return err
			}

		// Everything else (devices, named pipes, sockets) is skipped.
		}
		return nil
	})
}

// copyRegularFile copies the contents of srcPath into dstFS at dstPath,
// then sets permissions and ownership.
func copyRegularFile(srcPath, dstPath string, dstFS filesystem.FileSystem, mode os.FileMode, st *syscall.Stat_t) error {
	data, err := os.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", srcPath, err)
	}

	dst, err := dstFS.OpenFile(dstPath, os.O_CREATE|os.O_RDWR)
	if err != nil {
		return fmt.Errorf("create %s in image: %w", dstPath, err)
	}
	defer dst.Close()

	// Write in one shot so go-diskfs allocates a single contiguous extent
	// for the whole file. Incremental writes (e.g. via io.Copy) create one
	// extent per chunk and exhaust the 4 inline inode slots, triggering a
	// multi-level extent tree that is unimplemented in go-diskfs v1.8.0.
	if _, err := dst.Write(data); err != nil {
		return fmt.Errorf("copy %s: %w", dstPath, err)
	}
	if err := dstFS.Chmod(dstPath, mode); err != nil && !errors.Is(err, filesystem.ErrNotImplemented) {
		return fmt.Errorf("chmod %s: %w", dstPath, err)
	}
	if err := dstFS.Chown(dstPath, int(st.Uid), int(st.Gid)); err != nil && !errors.Is(err, filesystem.ErrNotImplemented) {
		return fmt.Errorf("chown %s: %w", dstPath, err)
	}
	return nil
}

// writeTextFile writes content to path inside dstFS, creating parent
// directories as needed. Mkdir is idempotent in go-diskfs.
func writeTextFile(dstFS filesystem.FileSystem, path string, content []byte) error {
	path = strings.TrimPrefix(path, "/")
	dir := filepath.Dir(path)
	if dir != "." {
		if err := dstFS.Mkdir(dir); err != nil {
			return fmt.Errorf("mkdir %s: %w", dir, err)
		}
	}
	f, err := dstFS.OpenFile(path, os.O_CREATE|os.O_RDWR|os.O_TRUNC)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	if _, err := f.Write(content); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}
