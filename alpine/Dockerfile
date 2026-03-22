FROM alpine:3.21 

RUN apk add --no-cache \
     linux-lts \
     openrc \
     eudev

RUN rc-update add udev sysinit && \
    rc-update add udev-trigger sysinit && \
    rc-update add udev-settle sysinit && \
    rc-update add localmount boot

# Add serial console getty for VM use (arm64: ttyAMA0, amd64: ttyS0)
RUN printf 'ttyAMA0::respawn:/sbin/getty -L ttyAMA0 115200 vt100\nttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100\n' >> /etc/inittab

RUN echo "root:root" | chpasswd
