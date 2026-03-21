FROM alpine:3.21 AS rootfs

RUN apk add --no-cache \
     linux-lts \
     openrc

RUN echo "root:root" | chpasswd
