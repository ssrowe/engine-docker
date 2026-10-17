# Releasing images

How Open Integration Engine images are built, published and promoted. For maintainers. User-facing documentation is in the [README](../README.md).

## Overview

```
 upstream release v4.7.0            push to main changing deploy/ (incl. Renovate base image updates)
          │                                         │
          ▼                                         ▼
 watch.yaml (hourly) ───────────────────────────────┤  starts publish.yaml for each version
          │                                         │
          ▼                                         ▼
 publish.yaml ── builds 3 variants × 2 platforms, smoke-tests each, pushes 4.7.0-rN,
                 signs, creates pre-release 4.7.0-rN: the candidate
          │
          │  release candidates, or promote_now: at once
          │  otherwise: after the soak, if no release-blocker issue
          ▼
 promote.yaml (daily, or by hand) ── moves 4.7.0, 4.7, latest, ... to 4.7.0-rN;
                                     marks the release as a full release
```

- **Revision (`-rN`)**: one build of one upstream version. N starts at 1 and goes up each time that version is published again, for example after a base image update. A revision's tags never move.
- **Candidate**: a revision whose GitHub Release is a pre-release. Its immutable tags exist; the mutable tags don't point at it yet.
- **Promoted**: a revision whose GitHub Release is a full release. The mutable tags point at the promoted revision of each version.
- **Superseded**: a candidate with a newer revision of the same version. It is never promoted; the daily run adds a note to its release.

GitHub Releases in this repository are the record of what was published and promoted. Don't delete them; the workflows read them to choose revision numbers, soak times and which version is latest.

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

## Soak

A candidate's soak is the `Soak: N hours` line in its release notes, written by `publish.yaml` from its `soak_hours` input. The daily promote run promotes a candidate once that many hours have passed since its release was created.

| Candidate | Soak | Set by |
|---|---|---|
| Upstream release candidate (`4.7.0-rc1`) | none; promoted by the publish run | `publish.yaml` |
| GA release identical to its last release candidate | `SOAK_HOURS_FAST` (48) | `watch.yaml` |
| Any other GA release | `SOAK_HOURS_FULL` (168) | `watch.yaml` |
| Rebuild after a change to the image definition | `SOAK_HOURS_FAST` (48) | `watch.yaml` |
| Manual publish without `soak_hours` | `SOAK_HOURS_FULL` (168) | `publish.yaml` |

"Identical" means GitHub's compare API reports `identical` for `v<last rc>...v<version>` in the upstream repository: the GA tag is on the same commit as the release candidate that was already tested.

## Blocking a promotion

A candidate isn't promoted while an **open** issue labelled **`release-blocker`** mentions it in its title or body:

- A mention of the version (`4.7.0`) blocks every revision of it. A mention of one revision (`4.7.0-r2`) blocks only that revision.
- `4.7.0-rc1` also counts as a mention of `4.7.0`, which errs on the side of blocking.
- Anyone can open an issue; the [image candidate problem](../.github/ISSUE_TEMPLATE/image-candidate-problem.yml) template asks for the image, version and what broke. Only people with triage access or above can add labels, so only maintainers can block.
- While a candidate is blocked, the daily run skips it, comments once on each blocking issue ("Promotion of `4.7.0-r2` is blocked by this issue.") and adds "Blocked by #N." to the release notes once. The soak time keeps counting.

To unblock, close the issue or remove the label. The next daily run promotes the candidate if its soak is over; or [promote it by hand](#promoting).

To fix instead, merge the fix: the rebuild creates a new revision with a new soak, which supersedes the blocked one. The issue stays open until a maintainer closes it.

To promote despite a blocker, run `promote.yaml` with `force=true`. The run log shows who did it.

Blocking doesn't undo a promotion that already happened; [roll back](#rolling-back) instead.

## Workflows

All cron times are UTC. CI and publish builds pull Docker Hub images through Google's mirror, `mirror.gcr.io` (BuildKit config in `setup-buildx-action`), so they don't count against Docker Hub's pull limits; the promote job's tag operations still do, which is why it checks one tag per variant.

### CI ([`ci.yaml`](../.github/workflows/ci.yaml))

- **Triggers**: pull requests, pushes to `main` and `integration`, manual runs.
- **Permissions**: `contents: read`. No secrets, so pull requests from forks are safe.
- **Jobs**: lint (shellcheck, hadolint, actionlint, `tags-test.sh`, `promote-test.sh`, README size for Docker Hub), then a test job per variant on amd64 and arm64 runners: build, `test/smoke.sh` with Derby and PostgreSQL, `test/entrypoint-test.sh`, and a Trivy scan that reports without failing.

### Watch ([`watch.yaml`](../.github/workflows/watch.yaml))

- **Triggers**: hourly at minute 17; pushes to the default branch that change `deploy/Dockerfile`, `deploy/docker-bake.hcl` or `deploy/entrypoint.sh`; manual runs.
- **What it does**: on the schedule, starts `publish.yaml` for every published upstream release at or above `MIN_VERSION` that has no release here, with the soak from the table above. On a push, starts a [rebuild](#rebuilds). It skips a version whose publish is already running.
- **Permissions**: `actions: write` (start `publish.yaml`; dispatches from `GITHUB_TOKEN` are allowed to start workflows), `contents: read`.

### Publish ([`publish.yaml`](../.github/workflows/publish.yaml))

- **Triggers**: manual runs; started by `watch.yaml`.
- **Inputs**: `version` (upstream version without the `v`, e.g. `4.6.0`), `promote_now` (promote without a soak), `soak_hours`.
- **Jobs**:
  1. `prepare`: finds the upstream `oie_unix_*.tar.gz` and its SHA-256 in the release's `sha256sums`, failing if either is missing, and picks N = 1 + the highest existing `<version>-rN` release.
  2. `build`: each variant on a native amd64 and arm64 runner. It runs `test/smoke.sh` (Derby) against the build first, since CI only tests the default version, then pushes it by digest to every repository in `IMAGE_REPOS` with an SBOM and `mode=max` provenance.
  3. `merge`: joins the two platforms into one index per variant, tags it with the revision tags, and signs it with cosign in each registry.
  4. `release`: creates the pre-release `<version>-rN` on the commit that was built. The notes list the digests, tags, upstream tarball, its SHA-256, base images, the soak and a test checklist.
  5. `promote`: calls `promote.yaml` for upstream pre-releases or when `promote_now` is set.
- **Permissions**: `contents: write` (release), `packages: write` (GHCR), `id-token: write` (cosign keyless signing).

### Promote ([`promote.yaml`](../.github/workflows/promote.yaml))

- **Triggers**: daily at 06:23; manual runs; called by `publish.yaml`.
- **Inputs**: `version`, `revision` (empty for the newest), `force` (ignore blockers; manual runs only).
- **What it does**: runs [`deploy/promote.sh`](../deploy/promote.sh). The daily run finds candidates whose soak is over and that aren't blocked, and notes superseded and blocked candidates. For each revision to promote, it works out whether the version is the highest promoted version and the highest patch of its minor, points the mutable tags at the revision's existing index digest with `docker buildx imagetools create` (nothing is rebuilt or re-signed, and the result is checked against the signed digest), and marks the release as a full release. Only stable versions are marked as GitHub's "latest" release, which the README's "latest image" badge shows. When the latest stable version is promoted, it also copies `README.md` to the Docker Hub description.
- **Permissions**: `contents: write` (release notes), `issues: write` (blocker comments), `packages: write` (GHCR).

### Variables and secrets

| Name | Kind | Used by | Value |
|---|---|---|---|
| `IMAGE_REPOS` | variable | publish, promote | Space-separated repositories, e.g. `docker.io/openintegrationengine/engine ghcr.io/openintegrationengine/engine` |
| `DOCKERHUB_USERNAME` | variable | publish, promote | Docker Hub user or organization the token belongs to |
| `MIN_VERSION` | variable | watch | Oldest upstream version to publish; default `4.6.0` |
| `SOAK_HOURS_FAST` | variable | watch | Default `48` |
| `SOAK_HOURS_FULL` | variable | watch, publish, promote | Default `168` |
| `DOCKERHUB_TOKEN` | secret | publish, promote | Docker Hub access token. Pushing needs Read & Write. Updating the description needs Read, Write & Delete ([dockerhub-description](https://github.com/peter-evans/dockerhub-description)); with a Read & Write token only that job fails. |

GHCR uses the workflow's `GITHUB_TOKEN`. The jobs that use `DOCKERHUB_TOKEN` run in the `release` environment, so it can be an environment secret limited to `main`; in a fork, a repository secret works too.

## Rebuilds

A push to the default branch that changes the image definition (`deploy/Dockerfile`, `deploy/docker-bake.hcl`, `deploy/entrypoint.sh`) publishes a new revision of the supported versions, each with the short soak:

- the newest promoted version of each of the two newest minors, e.g. 4.7.2 and 4.6.5;
- the newest promoted release candidate, if it is newer than those, e.g. 4.8.0-rc1.

### Renovate

[`renovate.json`](../renovate.json) keeps the pinned digests current: the Temurin base images in `docker-bake.hcl`, the Alpine downloader in the Dockerfile, PostgreSQL in `test/compose.postgres.yaml`, the tool images in `ci.yaml`, and the actions (pinned by commit). Digest, pin and patch updates merge automatically once CI passes, and a merged base image update starts a rebuild. Minor updates open a PR for review. Major updates wait for approval on the Dependency Dashboard issue that Renovate keeps open. Renovate PRs are labelled `dependencies`, and Renovate opens security PRs for vulnerabilities it finds in the dependencies.

A new Java major version is not proposed. The images use one set of base images for every OIE version, so moving to a new Java version, or a new Ubuntu or Alpine release, would also change the images of older supported versions when they are rebuilt. How to handle that is an open question.

## Runbooks

### Publishing

```sh
gh workflow run publish.yaml -f version=4.6.0
```

This creates the candidate `4.6.0-rN` with the full soak. Add `-f soak_hours=48` for a different soak, or `-f promote_now=true` to promote at once. Running it again for the same version creates the next revision.

### Promoting

```sh
gh workflow run promote.yaml -f version=4.6.0             # newest revision
gh workflow run promote.yaml -f version=4.6.0 -f revision=2
gh workflow run promote.yaml -f version=4.6.0 -f force=true   # despite release-blocker issues
gh workflow run promote.yaml                                  # what the daily run does, now
```

A manual promotion doesn't wait for the soak.

### Shipping a security fix without the soak

Merge the fix (or let Renovate merge the base image update), wait for the rebuild's publish runs, then promote each new revision by hand as above. If the fix doesn't change `deploy/`, publish with `-f promote_now=true` instead.

### Rolling back

Promote the previous revision. The mutable tags move back to it without a rebuild:

```sh
gh workflow run promote.yaml -f version=4.6.0 -f revision=1
```

The later revision's release stays a full release; edit its notes to say it was rolled back. To withdraw a whole version from `latest`, promote the previous version again.

### A candidate seems stuck

Read the daily promote run's log: it prints every candidate that is soaking (with hours so far), blocked (with the issues) or superseded. Check the `Soak:` line in the release notes. To promote now, [promote it by hand](#promoting).

### The watcher missed a release

Run `gh workflow run watch.yaml`, or publish the version by hand. The watcher only sees published (not draft) upstream releases at or above `MIN_VERSION`, and needs both `oie_unix_*.tar.gz` and `sha256sums` assets; the failed publish run says which is missing.

### Scheduled runs stopped

GitHub disables scheduled workflows after 60 days without repository activity; Renovate's merges count as activity. Re-enable them on each workflow's page in the Actions tab, or with `gh workflow enable watch.yaml` and `gh workflow enable promote.yaml`. Manual runs always work.

### Rotating the Docker Hub token

Create a new token on Docker Hub, then `gh secret set DOCKERHUB_TOKEN` (with `--env release` if it's an environment secret), run `promote.yaml` for the latest version to check it, and revoke the old token.

## Setting up a fork for testing

1. Fork the repository. Make a branch, e.g. `integration`, the fork's default branch: manual and scheduled runs only use workflows on the default branch.
2. Create test repositories, e.g. `docker.io/<you>/oie-engine-test`, and a Docker Hub access token.
3. Set the variables and secret, with short soaks for testing:
   ```sh
   gh variable set IMAGE_REPOS --body "docker.io/<you>/oie-engine-test ghcr.io/<you>/oie-engine-test"
   gh variable set DOCKERHUB_USERNAME --body <you>
   gh variable set MIN_VERSION --body 4.6.0-rc1
   gh variable set SOAK_HOURS_FAST --body 0.1
   gh variable set SOAK_HOURS_FULL --body 0.2
   gh secret set DOCKERHUB_TOKEN
   gh label create release-blocker --color B60205
   ```
4. Enable workflows in the fork's Actions tab, and issues in its settings (forks have them off; promotion fails closed when it can't check for blockers). After the first publish, make the GHCR package public in its settings, so it can be pulled and verified anonymously.
5. Signatures from the fork have the identity `https://github.com/<you>/engine-docker/.github/workflows/publish.yaml@refs/heads/<branch>`.
6. To test Renovate, install the [Renovate app](https://github.com/apps/renovate) on the fork and turn on "Allow auto-merge" (`gh repo edit --enable-auto-merge`).

## Activating upstream

An organization admin:

1. Sets `IMAGE_REPOS="docker.io/openintegrationengine/engine ghcr.io/openintegrationengine/engine"`, `DOCKERHUB_USERNAME` and `MIN_VERSION=4.6.0`. The soak variables can stay unset.
2. Adds `DOCKERHUB_TOKEN` as an organization access token, ideally in a `release` environment limited to `main`.
3. Creates the `release-blocker` label, installs the Renovate app, and turns on "Allow auto-merge" in the repository settings, so Renovate's updates merge as soon as CI passes.
4. Runs `gh workflow run publish.yaml -f version=4.6.0 -f promote_now=true`.
5. Makes the GHCR package public.
