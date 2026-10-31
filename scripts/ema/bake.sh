#!/bin/sh
# Installs named parts of upstream's arm64 Debian 13 build image.
#
#   scripts/ema/bake.sh <bake dir> <section>...
#
# <bake dir> is what `node scripts/build/ci-images/spec.ts linux-aarch64-debian`
# writes: bootstrap.sh, a generated script made of "# ---- <name>" sections, plus
# the files it reads (xmac.mjs). Upstream bakes the whole script into a VM image
# with a Buildkite agent, Tailscale, Docker and test fixtures. Only the sections
# a build needs are run here, unchanged and in the script's own order, so the
# versions and checksums stay the ones upstream pins for this commit.
#
# Runs as root. A section that already ran with the same text is skipped, so a
# reused container only runs what changed.
set -eu

[ $# -ge 2 ] || { echo "usage: $0 <bake dir> <section>..." >&2; exit 2; }
BAKE_DIR=$(cd "$1" && pwd)
shift
bootstrap="$BAKE_DIR/bootstrap.sh"
[ -f "$bootstrap" ] || { echo "error: $bootstrap not found" >&2; exit 1; }

markers=/var/lib/ema-bake
mkdir -p "$markers/done" "$BAKE_DIR/observed"

for wanted in "$@"; do
  grep -qx "# ---- $wanted" "$bootstrap" || { echo "error: no section \"$wanted\" in $bootstrap" >&2; exit 1; }
done

# Every section of the script, in order; keep the ones asked for.
wanted=" $* "
sed -n 's/^# ---- //p' "$bootstrap" | while read -r section; do
  case "$wanted" in *" $section "*) ;; *) continue ;; esac

  body=$(awk -v s="# ---- $section" '$0 == s { on = 1; next } /^# ---- / { on = 0 } on' "$bootstrap")
  sum=$(printf '%s' "$body" | sha256sum | cut -c1-16)
  if [ -f "$markers/done/$section.$sum" ]; then
    echo "bake: $section (already installed)"
    continue
  fi

  # A sysroot or SDK section unpacks over what is there; start it clean so a
  # second run cannot leave files of an older pin behind.
  case "$section" in
    glibc-sysroot) rm -rf /opt/linux-sysroot-glibc /opt/linux-sysroot-glibc-arm64 ;;
    musl-sysroot) rm -rf /opt/linux-sysroot-musl /opt/linux-sysroot-musl-arm64 ;;
    windows-sysroot) rm -rf /opt/winsysroot /opt/winsysroot.cache ;;
    macos-sdk) rm -rf /opt/macos-sdk ;;
  esac

  echo "bake: $section"
  start=$(date +%s)
  {
    echo 'set -eu'
    echo "BAKE_DIR='$BAKE_DIR'"
    echo 'REPO_COMMIT=ema; IMAGE_NAME=ema'
    echo 'export DEBIAN_FRONTEND=noninteractive'
    printf '%s\n' "$body"
  } > "$markers/$section.sh"
  sh "$markers/$section.sh" < /dev/null
  rm -f "$markers/done/$section".*
  touch "$markers/done/$section.$sum"
  echo "bake: $section done in $(($(date +%s) - start))s"
done
