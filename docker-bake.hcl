# docker-bake.hcl

variable "DISTROS" {
  default = [
    "alpine",
    "debian",
    "debian-vscode"
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
  context    = "${distro}"
  dockerfile = "Dockerfile"
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

  args = {
    EFI_SIZE = "64M"
    DISTRO   = distro
  }

  output = ["./output/${distro}"]
}
