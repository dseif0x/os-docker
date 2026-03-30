FROM debian:bookworm-slim 

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

# Resolve the correct kernel package for the target architecture.
# linux-image-amd64 / linux-image-arm64 are the meta-packages that pull in
# the latest kernel for that arch.
RUN case "${TARGETARCH}" in \
      amd64) KERNEL_PKG="linux-image-amd64" ;; \
      arm64) KERNEL_PKG="linux-image-arm64" ;; \
      *)     echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "${KERNEL_PKG}" \
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



RUN useradd -m -s /bin/bash kiosk
RUN usermod -aG video,input,tty kiosk
RUN echo "kiosk:kiosk" | chpasswd

RUN apt update && apt install -y cage wget gnupg2 mesa-utils vulkan-tools xwayland
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
RUN install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
RUN echo "deb [arch=arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
> /etc/apt/sources.list.d/vscode.list
RUN apt update && apt install -y code

COPY ./vscode-wayland.sh /usr/local/bin/vscode-wayland.sh
RUN chmod +rx /usr/local/bin/vscode-wayland.sh
COPY ./vscode-wayland.service /etc/systemd/system/vscode-wayland.service
RUN systemctl enable vscode-wayland.service