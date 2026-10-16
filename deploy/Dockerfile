# syntax=docker/dockerfile:1

# Build with docker-bake.hcl, which sets these per variant.
ARG BASE_IMAGE
ARG DISTRO

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS downloader

ARG OIE_RELEASE_URL
ARG OIE_RELEASE_SHA256

# OIE_RELEASE_URL is a URL, which hadolint can't tell from a local path.
# hadolint ignore=DL3020
ADD --checksum=sha256:${OIE_RELEASE_SHA256} ${OIE_RELEASE_URL} /tmp/engine.tar.gz

WORKDIR /opt/engine

RUN tar -xzf /tmp/engine.tar.gz --strip-components=1 \
    && rm -rf cli-lib manager-lib mirth-cli-launcher.jar oiecommand \
    && mkdir -p appdata custom-extensions logs \
    && touch derby.log \
    && chown -R 1000:0 appdata conf custom-extensions derby.log extensions logs server-launcher-lib oieserver.vmoptions \
    && chmod -R g=u appdata conf custom-extensions derby.log extensions logs server-launcher-lib oieserver.vmoptions

COPY --chmod=755 entrypoint.sh /opt/engine/entrypoint.sh


##########################################
#     Ubuntu (noble) based images
##########################################
FROM ${BASE_IMAGE} AS noble

# The base image's "ubuntu" user has uid 1000 and belongs to adm, sudo and other
# groups. Replace it with an "engine" user that keeps uid 1000, so existing
# appdata volumes still work, but has no extra groups.
# Package versions aren't pinned: the archive drops old versions, which would break builds.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && userdel --remove ubuntu \
    && groupadd --gid 1000 engine \
    && useradd --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin engine


##########################################
#     Alpine based images
##########################################
FROM ${BASE_IMAGE} AS alpine

# hadolint ignore=DL3018
RUN apk add --no-cache bash curl unzip \
    && addgroup -g 1000 engine \
    && adduser -D -H -u 1000 -G engine -s /sbin/nologin engine


##########################################
#     Final image, shared by every variant
##########################################
FROM ${DISTRO} AS engine

# Add OCI best-practice labels https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL "org.opencontainers.image.authors"="The Open Integration Engine Project and contributors" \
      "org.opencontainers.image.description"="An open source fork of the now closed-source Mirth Connect" \
      "org.opencontainers.image.licenses"="MPL-2.0" \
      "org.opencontainers.image.source"="https://github.com/OpenIntegrationEngine/engine-docker" \
      "org.opencontainers.image.title"="Open Integration Engine" \
      "org.opencontainers.image.url"="https://github.com/OpenIntegrationEngine/engine" \
      "org.opencontainers.image.vendor"="The Open Integration Engine Project"

COPY --from=downloader /opt/engine /opt/engine

# Fail the build if anything outside /opt/engine belongs to uid or gid 1000, so a
# future base image can't silently give the engine user access to it.
RUN found="$(find / -xdev \( -user 1000 -o -group 1000 \) ! -path '/opt/engine/*')" \
    && if [ -n "$found" ]; then printf 'Owned by uid/gid 1000 outside /opt/engine:\n%s\n' "$found" >&2; exit 1; fi

VOLUME /opt/engine/appdata
VOLUME /opt/engine/custom-extensions

WORKDIR /opt/engine
EXPOSE 8080 8443
USER 1000:1000

# Temurin's entrypoint adds the certificates in /certificates when USE_SYSTEM_CA_CERTS is set.
ENTRYPOINT ["/__cacert_entrypoint.sh", "./entrypoint.sh"]
CMD ["./oieserver"]
