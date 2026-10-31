# Patched Bun for ema

This branch (`ema-v1.4.4` of [bylocico/bun](https://github.com/bylocico/bun)) is upstream Bun
[`bun-v1.4.4`](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.4) plus three fixes that are
open upstream. The releases it produces are **not official oven-sh releases**.

## The patches

| Commit on this branch | Upstream PR | What it fixes |
| --- | --- | --- |
| net: fire socket.setTimeout() while the socket is still connecting | [oven-sh/bun#42399](https://github.com/oven-sh/bun/pull/42399) | `http.request({ timeout })` and `socket.setTimeout()` never fired during a TCP connect with a write queued, so a request to an unreachable host hung until the OS gave up. |
| net: fire socket.setTimeout() when the write queue stalls | [oven-sh/bun#42404](https://github.com/oven-sh/bun/pull/42404) | A peer that stopped reading silenced the idle timeout forever. |
| test runner: don't block in the poll after running immediates inside expect().resolves/.rejects | [oven-sh/bun#45029](https://github.com/oven-sh/bun/pull/45029) | `await expect(p).rejects` stalled for about a second per `setImmediate` hop while a socket kept the loop alive ([oven-sh/bun#45020](https://github.com/oven-sh/bun/issues/45020)). |

Each commit keeps its upstream message and tests. #42399 and #42404 both change
`Socket.prototype._onTimeout` in `src/js/node/net.ts`; the second applies on top of the first.
`test/ema/expect-rejects-setimmediate-stall.test.ts` is the #45020 reproduction, which the release
workflow runs against the built binaries.

The other commits on the branch are ema's own: the upstream workflows are removed (only
`.github/workflows/ema-release.yml` exists here), and `scripts/ema/`, this file and the release
workflow are added.

## Versioning

`bun --version` and `Bun.version` print the upstream version (`1.4.4`). A prerelease version such as
`1.4.4-ema.1` would fail semver range checks (`engines.bun`, `>=1.4.0`, setup-bun's version
matching), because prereleases never satisfy a plain range. The build is told apart by
`bun --revision`, which prints `1.4.4+<first 9 characters of this branch's commit>`; upstream's 1.4.4
prints `1.4.4+38afee6c8`. The release tag, e.g. `bun-v1.4.4-ema.1`, carries the patch-release number.

Builds pass `--canary=off`, as upstream's releases do. Without it the binary calls itself
`1.4.4-canary.1` and turns on canary-only behaviour (`bun upgrade` defaults to canary, among others).

## Cutting a release

One-time setup of the repository:

1. Settings → Actions → General: Actions enabled, and, if actions are restricted, `actions/*` and
   `docker/*` allowed. Either "Workflow permissions" setting works, because every job requests its
   own permissions (`contents: write` to create the release, `packages: write` for GHCR), but the
   organization must not cap the token below those.
2. Keep upstream's workflows disabled: run `scripts/ema-disable-upstream-workflows.sh` (needs `gh`,
   authenticated as a repository admin). Re-run it after **every** sync of the fork with upstream:
   a sync can add workflow files, and GitHub starts each new workflow out active.
3. After the first release, make the container package public, once: the organization's Packages →
   `bun` → Package settings → Change visibility → Public. (The organization must allow public
   packages.)

Each release:

1. Make sure the release branch is pushed, then either:
   - Actions → **ema release** → Run workflow, on branch `ema-v1.4.4`, with `release_tag`
     `bun-v1.4.4-ema.<n>`. The tag is created at the branch's commit when the release is published;
     or
   - push a tag yourself: `git tag bun-v1.4.4-ema.<n> ema-v1.4.4 && git push bylocico bun-v1.4.4-ema.<n>`.
2. The workflow builds the 8 targets, verifies all 12 assets, creates a **prerelease** with the zips
   and `SHASUMS256.txt`, then pushes `ghcr.io/bylocico/bun:<version>`, `:<version>-debian` and
   `:<version>-alpine` for linux/amd64 and linux/arm64. `<version>` is the tag without `bun-v`, e.g.
   `1.4.4-ema.1`.

The tag must match `bun-v<x.y.z>-ema.<n>`, and `<x.y.z>` must equal `package.json`'s version at the
commit being built. A tag whose release already exists is refused.

Installing it (the upstream install script always downloads from oven-sh, so fetch the zip):

```sh
curl -fsSLO https://github.com/bylocico/bun/releases/download/bun-v1.4.4-ema.1/bun-linux-x64.zip
unzip bun-linux-x64.zip && install -m 755 bun-linux-x64/bun ~/.bun/bin/bun
```

`oven-sh/setup-bun` takes a zip URL as `bun-download-url`. Docker images replace
`oven/bun:<version>` with `ghcr.io/bylocico/bun:<version>` (and `-alpine`, `-debian`).

## Build details

The workflow mirrors upstream CI (`.buildkite/ci.ts`): every target is cross-compiled on upstream's
arm64 Debian 13 "build" image. Upstream bakes that image as private AWS and Azure machine images and
does not publish it as a container image, so `scripts/ema/bake.sh` installs the parts a build needs
inside a `debian:trixie` container, from the bake script that `scripts/build/ci-images/spec.ts`
generates for this commit: the same pinned LLVM, Rust nightly, glibc (Ubuntu 20.04) and musl
sysroots, Windows SDK (via xwin) and macOS SDK (via xmac). Fetching the Windows and macOS SDKs
accepts Microsoft's and Apple's licence terms, as upstream's bake does. `scripts/ema/build-target.sh`
then runs `scripts/build.ts --profile=release --ci=on --canary=off --lto=off` with the target's
`--os`/`--arch`/`--abi`, and zips `<target>/bun` (or `bun.exe`).

- **LTO off by default.** Upstream releases are built with ThinLTO. `--lto=off` keeps the build
  within a GitHub-hosted runner's memory and the 6-hour job limit, at some cost in binary speed and
  size. The `lto` input turns it on.
- **x64 is always a baseline build** in Bun 1.4.4 (no AVX2 variant exists). The `-baseline` assets
  are the same binaries re-zipped under the historical names, as upstream's
  `.buildkite/scripts/upload-release.sh` does.
- **Signing.** The macOS arm64 binary carries the linker's ad-hoc signature, as upstream's does;
  macOS x64 is unsigned, as upstream's is. Upstream code-signs its Windows binaries; these are not.
- **Not built:** Android, FreeBSD and the `-profile` (unstripped) zips.

## Rebasing onto a new upstream tag

```sh
cd ~/git/bun
git fetch --no-prune-tags origin tag bun-v1.4.5        # never a plain `git fetch`: fetch.prunetags is on
git worktree add -b ema-v1.4.5 /tmp/bun-ema-v1.4.5 bun-v1.4.5
cd /tmp/bun-ema-v1.4.5
git cherry-pick <the three patch commits of ema-v1.4.4>   # skip any that upstream has merged
git cherry-pick <the ema commits: workflow removal, release workflow and scripts>
git rm -r --ignore-unmatch $(git ls-files .github/workflows | grep -v ema-release.yml) \
  .github/dependabot.yml .github/CODEOWNERS               # workflows that the new tag added
```

Then:

1. Resolve conflicts against the new code, keeping each patch's tests.
2. Update this file and `scripts/ema/release-notes.md` (the patch list, and the base tag where it is
   written out).
3. Build and run each patch's tests on the patched binary and on the official one; the official
   one must fail them.
4. `actionlint .github/workflows/ema-release.yml`; check that `scripts/ema/bake.sh` still finds
   every section it is asked for (`node scripts/build/ci-images/spec.ts linux-aarch64-debian` and
   look at the `# ---- ` names) and that `.buildkite/ci.ts` still builds the same targets.
5. Push the branch, run `scripts/ema-disable-upstream-workflows.sh`, then cut `bun-v1.4.5-ema.1`.
