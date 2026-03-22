FROM alpine:3.21 

RUN apk add --no-cache \
     linux-virt \
     openrc \
     eudev

RUN rc-update add udev sysinit && \
    rc-update add udev-trigger sysinit && \
    rc-update add udev-settle sysinit

RUN echo "root:root" | chpasswd
