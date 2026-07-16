#!/usr/bin/env bash
# Auto-bump the version: of any chart whose contents changed relative to a base
# ref, UNLESS the version was already bumped in this branch. Intended to run on
# Renovate (and other) PRs: Renovate updates an appVersion / image tag / values
# file but never touches the wrapper chart's own version:, so chart-releaser
# silently skips the release (skip_existing: true). This closes that gap.
#
# Usage:
#   .github/bump-chart-versions.sh [base-ref]     # default base: origin/main
#
# Bump is patch-level. For each changed chart it compares the working-tree
# version to the base-ref version; if unchanged, it bumps patch and rewrites
# Chart.yaml in place. Prints the charts it touched (one per line) to stdout so
# a workflow can decide whether to commit.
#
# Requires: yq (v4+), git.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chart-paths.sh
source "$DIR/lib/chart-paths.sh"

BASE="${1:-origin/main}"

bump_patch() {
  # major.minor.patch -> major.minor.(patch+1). Ignores any pre-release/build
  # suffix, which none of the charts in this repo use.
  local v="$1" major minor patch
  IFS='.' read -r major minor patch <<<"$v"
  echo "${major}.${minor}.$((patch + 1))"
}

bumped=()
for name in $(changed_charts "$BASE"); do
  file="$(chart_file "$name")"
  current="$(chart_version "$name")"
  base_version="$(base_chart_version "$name" "$BASE")"

  if [[ "$current" != "$base_version" ]]; then
    # Version already changed in this branch (human bumped it, or a prior run
    # of this script did). Leave it alone.
    echo "skip: $name version already changed ($base_version -> $current)" >&2
    continue
  fi

  new="$(bump_patch "$current")"
  yq -i ".version = \"$new\"" "$file"
  echo "bump: $name $current -> $new" >&2
  bumped+=("$name")
done

# Machine-readable output: the charts we actually bumped (empty if none).
((${#bumped[@]})) && printf '%s\n' "${bumped[@]}"
exit 0
