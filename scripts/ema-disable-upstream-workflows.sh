#!/bin/sh
# Disables every GitHub Actions workflow of a Bun fork except the ema release
# workflow, so that none of oven-sh/bun's own workflows can run there.
#
#   scripts/ema-disable-upstream-workflows.sh [owner/repo]   (default bylocico/bun)
#
# Re-run it after every sync of the fork with upstream: a sync can add new
# workflow files, and GitHub starts each new workflow out active.
# Needs the GitHub CLI, authenticated as someone who can administer the repo.
set -eu

repo=${1:-bylocico/bun}
keep=.github/workflows/ema-release.yml

gh workflow list --repo "$repo" --all --limit 1000 --json id,path,state \
  --jq ".[] | select(.path != \"$keep\") | select(.state == \"active\") | \"\(.id) \(.path)\"" |
  while read -r id path; do
    echo "disabling $path"
    gh workflow disable "$id" --repo "$repo"
  done

echo
gh workflow list --repo "$repo" --all --limit 1000
