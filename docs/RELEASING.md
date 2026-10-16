# Releasing images

How Open Integration Engine images are built, published and promoted. For maintainers. User-facing documentation is in the [README](../README.md).

## Overview

```
upstream release v4.6.0
        │
        ▼
publish.yaml ── builds 3 variants × 2 platforms, pushes 4.6.0-rN tags, signs, creates pre-release 4.6.0-rN
        │                                                                   (the "candidate")
        ▼
promote.yaml ── moves 4.6.0, 4.6, latest, ... to 4.6.0-rN; marks the release as a full release
```

- **Revision (`-rN`)**: one build of one upstream version. N starts at 1 and goes up each time that version is published again, for example after a base image update. A revision's tags never move.
- **Candidate**: a revision whose GitHub Release is a pre-release. Its immutable tags exist; the mutable tags don't point at it yet.
- **Promoted**: a revision whose GitHub Release is a full release. The mutable tags point at the promoted revision of each version.
- Upstream pre-releases (`4.7.0-rc1`) are promoted as soon as they're published.

GitHub Releases in this repository are the record of what was published and promoted. Don't delete them; the workflows read them to choose revision numbers and to work out which version is latest.

## Tags

[`deploy/tags.sh`](../deploy/tags.sh) is the only place tags are defined, and [`test/tags-test.sh`](../test/tags-test.sh) tests it.

| Kind | Example (`jre-noble` / `jdk-noble` / `jre-alpine`) | Set by |
|---|---|---|
| Revision | `4.6.0-r1`, `4.6.0-jre21-noble-r1` / `4.6.0-jdk-r1`, `4.6.0-jdk21-noble-r1` / `4.6.0-alpine-r1`, `4.6.0-jre21-alpine-r1` | publish; never moves |
| Version | `4.6.0`, `4.6.0-jre21-noble` / `4.6.0-jdk`, ... / `4.6.0-alpine`, ... | promote |
| Minor | `4.6` / `4.6-jdk` / `4.6-alpine`, only for the highest promoted patch of the minor | promote |
| Latest | `latest` / `latest-jdk` / `latest-alpine`, only for the highest promoted stable version | promote |
| Legacy | `4.6.0-ubuntu`, `4.6.0-ubuntu-jre` / `4.6.0-ubuntu-jdk` / `4.6.0-alpine-jre`, and the same with `latest-` when latest | promote |
| Release candidate | `4.7.0-rc1`, ... and `rc` / `rc-jdk` / `rc-alpine` for the highest pre-release | promote, at publish time |

"Highest" compares only promoted versions, so promoting 4.6.1 while 4.7.0 is latest moves `4.6.1` and `4.6` but not `latest`.

## Workflows

### CI ([`ci.yaml`](../.github/workflows/ci.yaml))

- **Triggers**: pull requests, pushes to `main` and `integration`, manual runs.
- **Permissions**: `contents: read`. No secrets, so pull requests from forks are safe.
- **Jobs**: lint (shellcheck, hadolint, actionlint, `tags-test.sh`, README size for Docker Hub), then a test job per variant on amd64 and arm64 runners: build, `test/smoke.sh` with Derby and PostgreSQL, `test/entrypoint-test.sh`, and a Trivy scan that reports without failing.

### Publish ([`publish.yaml`](../.github/workflows/publish.yaml))

- **Triggers**: manual runs.
- **Inputs**: `version` (upstream version without the `v`, e.g. `4.6.0`), `promote_now` (promote without a soak).
- **Jobs**:
  1. `prepare`: finds the upstream `oie_unix_*.tar.gz` and its SHA-256 in the release's `sha256sums`, failing if either is missing, and picks N = 1 + the highest existing `<version>-rN` release.
  2. `build`: each variant on a native amd64 and arm64 runner, with an SBOM and `mode=max` provenance, pushed by digest to every repository in `IMAGE_REPOS`.
  3. `merge`: joins the two platforms into one index per variant, tags it with the revision tags, and signs it with cosign in each registry.
  4. `release`: creates the pre-release `<version>-rN` on the commit that was built. The notes list the digests, tags, upstream tarball, its SHA-256, base images and a test checklist.
  5. `promote`: calls `promote.yaml` for upstream pre-releases or when `promote_now` is set.
- **Permissions**: `contents: write` (release), `packages: write` (GHCR), `id-token: write` (cosign keyless signing).

### Promote ([`promote.yaml`](../.github/workflows/promote.yaml))

- **Triggers**: manual runs; called by `publish.yaml`.
- **Inputs**: `version`, `revision` (empty for the newest).
- **What it does**: works out whether the version is the highest promoted version and the highest patch of its minor, points the mutable tags at the revision's existing index digest with `docker buildx imagetools create` (nothing is rebuilt or re-signed, and the job checks every tag has the signed digest), and marks the release as a full release. Only stable versions are marked as GitHub's "latest" release. When the latest stable version is promoted, it also copies `README.md` to the Docker Hub description.
- **Permissions**: `contents: write` (release), `packages: write` (GHCR).

### Variables and secrets

| Name | Kind | Used by | Value |
|---|---|---|---|
| `IMAGE_REPOS` | variable | publish, promote | Space-separated repositories, e.g. `docker.io/openintegrationengine/engine ghcr.io/openintegrationengine/engine` |
| `DOCKERHUB_USERNAME` | variable | publish, promote | Docker Hub user or organization the token belongs to |
| `DOCKERHUB_TOKEN` | secret | publish, promote | Docker Hub access token. Pushing needs Read & Write. Updating the description needs Read, Write & Delete ([dockerhub-description](https://github.com/peter-evans/dockerhub-description)); with a Read & Write token only that job fails. |

GHCR uses the workflow's `GITHUB_TOKEN`. The jobs that use `DOCKERHUB_TOKEN` run in the `release` environment, so it can be an environment secret limited to `main`; in a fork, a repository secret works too.

## Runbooks

### Publishing

```sh
gh workflow run publish.yaml -f version=4.6.0
```

This creates the candidate `4.6.0-rN`. To publish and promote in one go, add `-f promote_now=true`. Running it again for the same version creates the next revision.

### Promoting

```sh
gh workflow run promote.yaml -f version=4.6.0             # newest revision
gh workflow run promote.yaml -f version=4.6.0 -f revision=2
```

### Rolling back

Promote the previous revision. The mutable tags move back to it without a rebuild:

```sh
gh workflow run promote.yaml -f version=4.6.0 -f revision=1
```

The later revision's release stays a full release; edit its notes to say it was rolled back. To withdraw a whole version from `latest`, promote the previous version again.

### Rotating the Docker Hub token

Create a new token on Docker Hub, then `gh secret set DOCKERHUB_TOKEN`, run `publish.yaml` or `promote.yaml` to check it, and revoke the old token.

## Setting up a fork for testing

1. Fork the repository. Make a branch, e.g. `integration`, the fork's default branch: manual and scheduled runs only use workflows on the default branch.
2. Create test repositories, e.g. `docker.io/<you>/oie-engine-test`, and a Docker Hub access token.
3. Set the variables and secret:
   ```sh
   gh variable set IMAGE_REPOS --body "docker.io/<you>/oie-engine-test ghcr.io/<you>/oie-engine-test"
   gh variable set DOCKERHUB_USERNAME --body <you>
   gh secret set DOCKERHUB_TOKEN
   ```
4. After the first publish, make the GHCR package public in its settings, so it can be pulled and verified anonymously.
5. Signatures from the fork have the identity `https://github.com/<you>/engine-docker/.github/workflows/publish.yaml@refs/heads/<branch>`.

## Activating upstream

An organization admin:

1. Sets `IMAGE_REPOS="docker.io/openintegrationengine/engine ghcr.io/openintegrationengine/engine"` and `DOCKERHUB_USERNAME`.
2. Adds `DOCKERHUB_TOKEN` as an organization access token, ideally in a `release` environment limited to `main`.
3. Runs `gh workflow run publish.yaml -f version=4.6.0 -f promote_now=true`.
4. Makes the GHCR package public.
