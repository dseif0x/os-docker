# docker-bake.hcl

variable "DISTROS" {
  default = [
    "alpine",
    "debian"
  ]
}

target "linux_platforms" {
  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]
}

group "default" {
  targets = ["disk-image"]
}

target "rootfs" {
  name = "rootfs-${distro}"
  matrix = {
    distro = DISTROS
  }
  inherits   = ["linux_platforms"]
  context    = "."
  dockerfile = "${distro}/Dockerfile"
  output     = []
}

target "disk-image" {
  name = "disk-image-${distro}"
  matrix = {
    distro = DISTROS
  }
  inherits   = ["linux_platforms"]

  context    = "."
  dockerfile = "Dockerfile.disk-image"

  contexts = {
    "rootfs" = "target:rootfs-${distro}"
  }

  entitlements = ["security.insecure"]

  args = {
    IMG_SIZE = "4G"
    EFI_SIZE = "64M"
    DISTRO   = distro
  }

  output = ["./output/${distro}"]
}

# ── Raspberry Pi (arm64 only) ─────────────────────────────────────────────────

target "rootfs-raspbian" {
  context    = "."
  dockerfile = "raspbian/Dockerfile"
  platforms  = ["linux/arm64"]
  output     = []
}

target "disk-image-raspbian" {
  platforms  = ["linux/arm64"]
  context    = "."
  dockerfile = "Dockerfile.disk-image"

  contexts = {
    "rootfs" = "target:rootfs-raspbian"
  }

  entitlements = ["security.insecure"]

  args = {
    IMG_SIZE = "4G"
    EFI_SIZE = "256M"
    DISTRO   = "raspbian"
  }

  output = ["./output/raspbian"]
}
