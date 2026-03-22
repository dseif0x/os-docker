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