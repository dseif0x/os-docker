Test arm64 on m1 mac:
```
qemu-system-aarch64 \
-machine virt,accel=hvf \
-cpu host \
-smp 4 \
-m 2048 \
-drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,readonly=on" \
-drive "if=virtio,format=raw,file=output/disk.img" \
-nographic \
-serial mon:stdio
```

Test amd64 on m1 mac:
```
qemu-system-x86_64 \
-machine q35 \
-cpu qemu64 \
-smp 2 \
-m 2048 \
-drive "if=pflash,format=raw,file=${FIRMWARE},readonly=on" \
-drive "if=virtio,format=raw,file=${IMG}" \
-nographic \
-serial mon:stdio
```