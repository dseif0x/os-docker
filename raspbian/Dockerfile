FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# Add the Raspberry Pi Foundation repository (provides raspberrypi-bootloader)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg \
 && curl -fsSL https://archive.raspberrypi.com/debian/raspberrypi.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/raspberrypi-archive-keyring.gpg \
 && printf 'deb [arch=arm64 signed-by=/usr/share/keyrings/raspberrypi-archive-keyring.gpg] https://archive.raspberrypi.com/debian/ bookworm main\n' \
    > /etc/apt/sources.list.d/raspi.list \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      linux-image-arm64 \
      raspberrypi-bootloader \
      systemd systemd-sysv dbus \
      bash coreutils util-linux mount udev \
      iproute2 iputils-ping \
      curl ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN systemctl enable getty@tty1.service
RUN systemctl enable systemd-networkd.service

RUN printf '[Match]\nType=ether\n\n[Network]\nDHCP=yes\n' \
    > /etc/systemd/network/20-eth.network

RUN echo "root:root" | chpasswd
