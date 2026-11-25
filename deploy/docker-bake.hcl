# Build definition for the Open Integration Engine images.
#
# Run from the deploy/ directory:
#   docker buildx bake --print                                   # show the resolved build
#   docker buildx bake                                           # every variant, amd64 + arm64
#   docker buildx bake jre-noble --set '*.platform=linux/amd64' --load
#
# Any variable below can be overridden from the environment, e.g.
#   OIE_VERSION=4.6.0-rc1 OIE_RELEASE_SHA256=<sha256> docker buildx bake

variable "OIE_VERSION" {
  default = "4.6.0"
}

# Upstream release tarball and its sha256 from the release's sha256sums asset.
variable "OIE_RELEASE_URL" {
  default = "https://github.com/OpenIntegrationEngine/engine/releases/download/v${OIE_VERSION}/oie_unix_${replace(OIE_VERSION, ".", "_")}.tar.gz"
}

variable "OIE_RELEASE_SHA256" {
  default = "7c82e79027e671277e1d78d0f7bbb1c53ddf1be476f1e80c2ddbfcf7855900ea"
}

variable "JRE_NOBLE_IMAGE" {
  default = "eclipse-temurin:21.0.13.1_2-jre-noble@sha256:897ec01ae1350622de0d5393a48a4ffffee8fe1609f248f4389578b919eaf9f5"
}

variable "JDK_NOBLE_IMAGE" {
  default = "eclipse-temurin:21.0.13.1_2-jdk-noble@sha256:5f9489c60984e9715afba8e7da353e9d78d2a38c0517662f5cc29fc8094efe1f"
}

variable "JRE_ALPINE_IMAGE" {
  default = "eclipse-temurin:21.0.13.1_2-jre-alpine@sha256:5d7689f47d670aca766b9503a70bccc2d73b4eb9221ae8f714ae958313c4ce70"
}

# Image revision (the N in -rN); empty for local builds.
variable "REVISION" {
  default = ""
}

# engine-docker commit the image is built from; empty for local builds.
variable "GIT_SHA" {
  default = ""
}

group "default" {
  targets = ["jre-noble", "jdk-noble", "jre-alpine"]
}

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "engine"
  platforms  = ["linux/amd64", "linux/arm64"]
  args = {
    OIE_RELEASE_URL    = OIE_RELEASE_URL
    OIE_RELEASE_SHA256 = OIE_RELEASE_SHA256
  }
  labels = {
    "org.opencontainers.image.version"  = REVISION != "" ? "${OIE_VERSION}-r${REVISION}" : OIE_VERSION
    "org.opencontainers.image.revision" = GIT_SHA != "" ? GIT_SHA : null
  }
}

target "jre-noble" {
  inherits = ["_common"]
  args = {
    BASE_IMAGE = JRE_NOBLE_IMAGE
    DISTRO     = "noble"
  }
  tags = ["oie-engine:local-jre-noble"]
}

target "jdk-noble" {
  inherits = ["_common"]
  args = {
    BASE_IMAGE = JDK_NOBLE_IMAGE
    DISTRO     = "noble"
  }
  tags = ["oie-engine:local-jdk-noble"]
}

target "jre-alpine" {
  inherits = ["_common"]
  args = {
    BASE_IMAGE = JRE_ALPINE_IMAGE
    DISTRO     = "alpine"
  }
  tags = ["oie-engine:local-jre-alpine"]
}
