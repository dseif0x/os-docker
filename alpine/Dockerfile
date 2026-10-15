FROM alpine:3.21

# linux-firmware-none satisfies linux-lts' firmware dependency without pulling
# in several hundred MB of device firmware a VM never loads.
# e2fsprogs provides fsck.ext4 so OpenRC can check the root filesystem at boot.
RUN apk add --no-cache \
     linux-lts \
     linux-firmware-none \
     openrc \
     eudev \
     ifupdown-ng \
     e2fsprogs

RUN rc-update add udev sysinit && \
    rc-update add udev-trigger sysinit && \
    rc-update add udev-settle sysinit && \
    rc-update add localmount boot && \
    rc-update add networking default

RUN printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n' \
    > /etc/network/interfaces

# Serial console getty for VM use (arm64: ttyAMA0, amd64: ttyS0)
RUN printf 'ttyAMA0::respawn:/sbin/getty -L ttyAMA0 115200 vt100\nttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100\n' >> /etc/inittab

RUN echo "root:root" | chpasswd
