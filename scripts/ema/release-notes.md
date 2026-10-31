> [!WARNING]
> **Patched Bun — not an official oven-sh release.** Built by the ema team from upstream
> [`@BASE_TAG@`](https://github.com/oven-sh/bun/releases/tag/@BASE_TAG@) plus the fixes below.
> Report problems with these builds to bylocico, not to oven-sh.

`bun --version` prints `@BASE_VERSION@`, the upstream version, so that version checks keep working.
`bun --revision` prints `@REVISION@`: the commit of this build, which tells it apart from upstream's
`@BASE_VERSION@` build.

## Patches on top of @BASE_TAG@

- **net: fire `socket.setTimeout()` while the socket is still connecting** —
  [oven-sh/bun#42399](https://github.com/oven-sh/bun/pull/42399). `http.request({ timeout })` and
  `socket.setTimeout()` never fired while a TCP connect was outstanding with a write queued.
- **net: fire `socket.setTimeout()` when the write queue stalls** —
  [oven-sh/bun#42404](https://github.com/oven-sh/bun/pull/42404). A peer that stops reading no longer
  silences the idle timeout forever.
- **test runner: don't block in the poll after running immediates inside `expect().resolves`/`.rejects`** —
  [oven-sh/bun#45029](https://github.com/oven-sh/bun/pull/45029), fixing
  [oven-sh/bun#45020](https://github.com/oven-sh/bun/issues/45020).

## Build

- Commit: [`@SHA@`](https://github.com/@REPOSITORY@/commit/@SHA@)
- Built by GitHub Actions run [@RUN_ID@](https://github.com/@REPOSITORY@/actions/runs/@RUN_ID@), the way
  upstream CI builds (every target cross-compiled on the arm64 Debian 13 build image), with
  ThinLTO **@LTO@** and `--canary=off`. Upstream's official releases are built with ThinLTO and
  its CI's post-link optimisation steps, and its Windows binaries are code-signed; these builds
  skip those post-link steps and are not code-signed.
- The `-baseline` assets are the same binaries as the plain x64 ones (x64 is always built for the
  baseline CPU), published under the historical names as upstream does.
- `SHASUMS256.txt` is in upstream's format (not GPG-signed).
- Docker: `ghcr.io/@IMAGE_OWNER@/bun:@VERSION@` (Debian), `:@VERSION@-debian`, `:@VERSION@-alpine`.
