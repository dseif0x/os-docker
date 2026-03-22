FROM alpine:3.21 

RUN mkdir -p /etc/mkinitfs && \
    echo 'features="ata base ext4 virtio"' > /etc/mkinitfs/mkinitfs.conf

RUN apk add --no-cache \
     linux-virt \
     openrc

RUN echo "root:root" | chpasswd
