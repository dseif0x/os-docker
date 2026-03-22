# Building
```bash
docker buildx bake disk-image-alpine --no-cache --allow=security.insecure
```

```bash
docker buildx bake disk-image-debian --no-cache --allow=security.insecure
```

# Testing
Test arm64 on m1 mac:
```bash
qemu-system-aarch64 \
-machine virt,accel=hvf \
-cpu host \
-smp 4 \
-m 2048 \
-drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,readonly=on" \
-drive "if=virtio,format=raw,file=output/debian/linux_arm64/disk.img" \
-nographic \
-serial mon:stdio
```

Test amd64 on m1 mac:
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