```
qemu-system-aarch64 \
-machine virt,accel=hvf \
-cpu host \
-smp 4 \
-m 2048 \
-drive "if=pflash,format=raw,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,readonly=on" \
-drive "if=virtio,format=raw,file=output/disk.img" \
-netdev user,id=net0 \
-device virtio-net-pci,netdev=net0 \
-nographic \
-serial mon:stdio
```