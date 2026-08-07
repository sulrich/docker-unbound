# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Multi-arch Docker image for the [Unbound](https://unbound.nlnetlabs.nl/) recursive DNS resolver. Forked from `MatthewVance/unbound-docker-rpi` and simplified. Targets `linux/amd64` and `linux/arm64` (Raspberry Pi 3+ and standard x86 hosts). 32-bit ARM (`linux/arm/v7`) was dropped in favor of native ARM build runners. Published to `ghcr.io/sulrich/docker-unbound`.

## Bumping the Unbound version

A version bump touches **two** values that must stay in sync; mismatches will break either the build or the release tagging:

1. `Dockerfile` — the two global `ARG`s declared before the first `FROM`: `ARG UNBOUND_VERSION` and `ARG UNBOUND_SHA256`. These are the single source of truth. Everything downstream derives from them: each stage re-declares the `ARG`s to pull them into scope, the builder's `UNBOUND_DOWNLOAD_URL` is built from `${UNBOUND_VERSION}`, and the runtime image label reuses the version. The SHA256 is published alongside the tarball at `https://nlnetlabs.nl/downloads/unbound/unbound-<version>.tar.gz.sha256`.
2. The release is triggered by pushing a git tag of the form `v<version>` (e.g. `v1.25.0`). The release workflow strips the leading `v` and uses that as the image tag.

Note: because the `Dockerfile` now declares `ARG UNBOUND_VERSION`, the `UNBOUND_VERSION` build-arg passed by the build/release workflows is live — it overrides the hardcoded default. If you override the version via build-arg, you must also pass a matching `UNBOUND_SHA256` build-arg, or the `sha256sum -c` check will fail. For normal tag-based releases the `ARG` defaults in the Dockerfile remain the source of truth.

## Build / test / release flow

Both workflows use a **matrix on native runners** to avoid QEMU emulation: `ubuntu-latest` for amd64 and `ubuntu-24.04-arm` for arm64. Each leg builds + tests in parallel; this is the central design choice that keeps releases fast.

- **PR builds** (`.github/workflows/docker-build.yml`): matrix builds a test image per arch on its native runner, runs `data/test.sh` inside it (starts unbound, queries cloudflare.com and google.com via `drill`). No push. The PR is green only if both arches build and test cleanly.
- **Releases** (`.github/workflows/docker-release.yml`): three jobs — `setup` (resolves version from the `v*` tag or workflow input), `build` (matrix: per-arch build + test + push-by-digest to GHCR; each leg uploads its digest as a workflow artifact), and `merge` (downloads digest artifacts and calls `docker buildx imagetools create` to assemble the final multi-arch manifest with version + optional `latest` tags). `latest` is tagged automatically on git-tag pushes; on manual dispatch it's gated by the `tag_as_latest` input.
- The GHA build cache is scoped per arch (`scope=amd64` / `scope=arm64`) so matrix legs don't stomp on each other.
- Local test of the image: `docker build -t unbound-test . && docker run --rm unbound-test /test.sh`

## Image architecture

Two-stage build (`Dockerfile`):

1. **Builder stage** (`debian:bookworm AS unbound`): downloads the Unbound tarball, verifies SHA256, compiles with libevent + libnghttp2 + TFO, installs to `/opt/unbound`, then purges build deps. The compiled `unbound.conf` is moved aside to `unbound.conf.example` so the runtime entrypoint can generate one fresh.
2. **Runtime stage** (`debian:bookworm`): copies `/opt` from the builder, installs only the runtime shared libs (libssl3, libevent, libnghttp2, libexpat1, ldnsutils for `drill`), creates the `_unbound` user, and copies `data/` to `/` (so `/unbound.sh` and `/test.sh` land at the root, and `/opt/unbound/etc/unbound/{a,srv,forward}-records.conf` are seeded).

Healthcheck: `drill @127.0.0.1 cloudflare.com` every 30s.

## Runtime entrypoint: `data/unbound.sh`

This is the container `CMD`. Important behaviors:

- **Config is generated at container start, not baked into the image.** On first run, if `/opt/unbound/etc/unbound/unbound.conf` does not exist, the script writes one from a heredoc, substituting `@MSG_CACHE_SIZE@`, `@RR_CACHE_SIZE@`, `@THREADS@`, `@SLABS@` based on available memory (read from `/proc/meminfo` and the cgroup memory limit) and `nproc`.
- This means **mounting your own `unbound.conf` at `/opt/unbound/etc/unbound/unbound.conf` skips the generator entirely** — your config is used as-is.
- The generated config `include:`s `a-records.conf`, `srv-records.conf`, and `forward-records.conf` from the same directory; the defaults in `data/opt/unbound/etc/unbound/` are seeded into the image and intended to be overridden via volume mount.
- After config generation: copies `/dev/{random,urandom,null}` into a chroot-style `/opt/unbound/etc/unbound/dev/`, fetches the root trust anchor with `unbound-anchor`, then `exec`s `unbound -d`.

When editing `unbound.sh`, remember the `@TOKEN@` placeholders are substituted by `sed`; introducing new tokens requires adding a matching `-e` to the sed call.

## Notes from the fork

Upstream config patterns from `MatthewVance/unbound-docker-rpi` were largely left intact — the maintainer's stated workflow is to override everything via mounted volumes rather than tune the generated defaults. Don't assume the generated `unbound.conf` reflects deep intentional tuning for this fork; treat it as upstream's defaults.
