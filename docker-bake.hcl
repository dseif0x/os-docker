# docker-bake.hcl
#
#   docker buildx bake                      # every distro, amd64 + arm64
#   docker buildx bake disk-image-alpine    # one distro, both archs
#   docker buildx bake disk-image-debian --set "*.platform=linux/arm64"
#
# Distro-agnostic: every entry in DISTROS is a directory containing a
# Dockerfile that produces a bootable rootfs. To add a distro, create the
# directory and append its name to DISTROS. Each one gets a rootfs-<distro>
# target (the Dockerfile) and a disk-image-<distro> target that packs it into
# output/<distro>/.

variable "DISTROS" {
  default = ["alpine", "debian", "debian-vscode"]
}

variable "EFI_SIZE" {
  default = "64M"
}

target "linux_platforms" {
  platforms = ["linux/amd64", "linux/arm64"]
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
  context    = distro
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
    rootfs = "target:rootfs-${distro}"
  }

  args = {
    EFI_SIZE = EFI_SIZE
    DISTRO   = distro
  }

  output = ["./output/${distro}"]
}
