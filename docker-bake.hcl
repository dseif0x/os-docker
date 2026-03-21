# docker-bake.hcl

# ── Variables ─────────────────────────────────────────────────────────────────
variable "IMAGE_SIZE" {
  default = "4G"
}

variable "OUTPUT_DIR" {
  default = "./output"
}

# ── Platform matrix ───────────────────────────────────────────────────────────
# Shared platform list — inherit this in any target that should be
# cross-compiled. The rootfs stage uses QEMU for the cross-arch apt installs.
target "linux_platforms" {
  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]
}

# ── Groups ────────────────────────────────────────────────────────────────────
group "default" {
  targets = ["disk-image"]
}

target "rootfs" {
  inherits   = ["linux_platforms"]
  context    = "."
  dockerfile = "Dockerfile"
  target     = "rootfs"
  output     = []
}

target "disk-image" {
  inherits   = ["linux_platforms"]

  context    = "."
  dockerfile = "Dockerfile.disk-image"

  contexts = {
    "rootfs" = "target:rootfs"
  }

  entitlements = ["security.insecure"]

  args = {
    IMG_SIZE   = IMAGE_SIZE
  }

  output = ["${OUTPUT_DIR}"]
}
