# Debian kiosk that boots straight into VS Code under the Cage Wayland
# compositor. The first half mirrors debian/Dockerfile.
FROM debian:bookworm-slim

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

# linux-image-amd64 / linux-image-arm64 are the meta-packages that pull in
# the latest kernel for the target architecture.
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

RUN systemctl enable getty@tty1.service \
 && systemctl enable systemd-networkd.service \
 && printf '[Match]\nType=ether\n\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-eth.network \
 && echo "root:root" | chpasswd

# ── VS Code kiosk ────────────────────────────────────────────────────────────
# UID is fixed to 1000 because vscode-wayland.service hardcodes /run/user/1000.
RUN useradd -m -u 1000 -s /bin/bash -G video,input,tty,render kiosk \
 && echo "kiosk:kiosk" | chpasswd

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      cage xwayland gnupg mesa-utils vulkan-tools \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
 && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      > /etc/apt/sources.list.d/vscode.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends code \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 vscode-wayland.sh /usr/local/bin/vscode-wayland.sh
COPY vscode-wayland.service /etc/systemd/system/vscode-wayland.service
RUN systemctl enable vscode-wayland.service
