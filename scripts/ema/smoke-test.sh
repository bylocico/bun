#!/bin/sh
# Checks one built Bun binary inside the container it is meant to run in.
#
#   scripts/ema/smoke-test.sh <bun> <version> <revision> <arch> <platform> [<test file>]
#
# <version> is what `bun --version` must print (e.g. 1.4.4), <revision> what
# `bun --revision` must print (e.g. 1.4.4+aac7216de), <arch> and <platform> the
# expected process.arch (x64, arm64) and process.platform (linux, darwin,
# win32). With <test file>, it is copied to an empty
# directory (away from the repository's bunfig.toml and its test preload) and
# run with `bun test`.
set -eu

[ $# -ge 5 ] || { echo "usage: $0 <bun> <version> <revision> <arch> <platform> [<test file>]" >&2; exit 2; }
bun=$1
want_version=$2
want_revision=$3
want_arch=$4
want_platform=$5
test_file=${6:-}

fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   $1: $2"
  else
    echo "FAIL $1: got '$2', want '$3'"
    fail=1
  fi
}

# Windows prints CRLF line endings.
out() { "$@" | tr -d '\r'; }

check "bun --version" "$(out "$bun" --version)" "$want_version"
check "bun --revision" "$(out "$bun" --revision)" "$want_revision"
check "process.arch process.platform" "$(out "$bun" -e 'console.log(process.arch, process.platform)')" "$want_arch $want_platform"
check "Bun.version" "$(out "$bun" -e 'console.log(Bun.version)')" "$want_version"

if [ -n "$test_file" ]; then
  dir=$(mktemp -d)
  cp "$test_file" "$dir/"
  if (cd "$dir" && "$bun" test "./$(basename "$test_file")"); then
    echo "ok   bun test $(basename "$test_file")"
  else
    echo "FAIL bun test $(basename "$test_file")"
    fail=1
  fi
  rm -rf "$dir"
fi

exit "$fail"
