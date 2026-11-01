#!/bin/sh
# Builds one release target of the patched Bun, the way upstream CI does: on the
# arm64 Debian 13 "build" image of scripts/build/ci-images/spec.ts, which
# cross-compiles every target (macOS and Windows included).
#
# Run as root inside a debian:trixie arm64 container, from the repository root:
#
#   scripts/ema/build-target.sh <target> <out dir>
#
# <target> is an upstream asset name without ".zip", e.g. bun-linux-x64-musl.
# The script installs the parts of the build image that <target> needs (see
# scripts/ema/bake.sh), runs scripts/build.ts with the flags .buildkite/ci.ts
# passes for that target, and writes <out dir>/<target>.zip with upstream's
# layout (<target>/bun or <target>/bun.exe). x64 is always a baseline (nehalem)
# build upstream; the historical -baseline names are written too, as copies with
# the inner directory renamed, exactly as .buildkite/scripts/upload-release.sh
# does at release time.
#
# Environment:
#   GIT_SHA       commit to stamp as the revision (scripts/build/config.ts reads
#                 it); defaults to `git rev-parse HEAD`.
#   EMA_BAKE_DIR  output of `node scripts/build/ci-images/spec.ts
#                 linux-aarch64-debian`; generated here when missing (needs node).
#   EMA_LTO       "on" for upstream's ThinLTO release codegen; default "off".
set -eu

[ $# -eq 2 ] || { echo "usage: $0 <target> <out dir>" >&2; exit 2; }
target=$1
out=$2
repo=$(pwd)
lto=${EMA_LTO:-off}

case "$target" in
  bun-darwin-aarch64)     flags="--os=darwin --arch=aarch64"; sections="macos-sdk" ;;
  bun-darwin-x64)         flags="--os=darwin --arch=x64"; sections="macos-sdk" ;;
  bun-linux-x64)          flags="--os=linux --arch=x64 --abi=gnu"; sections="cross-compiler-rt glibc-sysroot" ;;
  bun-linux-aarch64)      flags="--os=linux --arch=aarch64 --abi=gnu"; sections="glibc-sysroot" ;;
  bun-linux-x64-musl)     flags="--os=linux --arch=x64 --abi=musl"; sections="cross-compiler-rt musl-sysroot" ;;
  bun-linux-aarch64-musl) flags="--os=linux --arch=aarch64 --abi=musl"; sections="musl-sysroot" ;;
  bun-windows-x64)        flags="--os=windows --arch=x64"; sections="windows-sysroot" ;;
  bun-windows-aarch64)    flags="--os=windows --arch=aarch64"; sections="windows-sysroot" ;;
  *) echo "error: unknown target: $target" >&2; exit 2 ;;
esac
case "$lto" in on | off) ;; *) echo "error: EMA_LTO must be on or off" >&2; exit 2 ;; esac

bake_dir=${EMA_BAKE_DIR:-$repo/build/ci-images/linux-aarch64-debian}
if [ ! -f "$bake_dir/bootstrap.sh" ]; then
  node scripts/build/ci-images/spec.ts linux-aarch64-debian
  bake_dir=$repo/build/ci-images/linux-aarch64-debian
fi

# The sections every build needs, then the target's sysroot or SDK.
# shellcheck disable=SC2086
sh scripts/ema/bake.sh "$bake_dir" packages agent-account nodejs bun bun-ninja cmake llvm rust $sections

# git comes from the bake's packages section; the base image has none.
git config --global --add safe.directory "$repo"
GIT_SHA=${GIT_SHA:-$(git rev-parse HEAD)}
export GIT_SHA

# shellcheck disable=SC1091
. /etc/profile.d/bun-ci.sh

build_dir="$repo/build/ema-$target"
echo "+ bun scripts/build.ts --profile=release --ci=on --canary=off --lto=$lto $flags --build-dir=$build_dir"
# shellcheck disable=SC2086
bun scripts/build.ts --profile=release --ci=on --canary=off --lto="$lto" $flags --build-dir="$build_dir"

case "$target" in bun-windows-*) exe=bun.exe ;; *) exe=bun ;; esac
[ -f "$build_dir/$exe" ] || { echo "error: $build_dir/$exe was not built" >&2; exit 1; }

mkdir -p "$out"
out=$(cd "$out" && pwd)
stage=$(mktemp -d)
zip_as() {
  mkdir -p "$stage/$1"
  cp "$build_dir/$exe" "$stage/$1/$exe"
  chmod 755 "$stage/$1/$exe"
  rm -f "$out/$1.zip"
  (cd "$stage" && cmake -E tar cf "$out/$1.zip" --format=zip "$1")
  echo "wrote $out/$1.zip"
}
zip_as "$target"
case "$target" in
  bun-darwin-x64 | bun-linux-x64 | bun-linux-x64-musl | bun-windows-x64) zip_as "$target-baseline" ;;
esac
rm -rf "$stage"
