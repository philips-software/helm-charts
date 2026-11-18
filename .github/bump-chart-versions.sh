#!/usr/bin/env bash
# Auto-bump the version: of any chart whose contents changed relative to a base
# ref, UNLESS the version was already bumped in this branch. Renovate bumps
# version: itself in-PR via the renovate.json5 bumpVersions rule, so this is
# the manual/agent recovery path for a PR that missed it, and the engine
# behind the push-time net in prepare-release.sh, which re-checks on the push
# to main in case a human PR merged without bumping (chart-releaser silently
# skips the release when version: is unbumped: skip_existing: true).
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

  # Charts that ship an install.sh self-verify marker must move it in lockstep
  # with version:, or action-helm-chart-repo skips packaging/publishing the
  # chart (marker/Chart.yaml mismatch guard).
  if [[ -n "$(install_sh_marker "$name")" ]]; then
    sed -i -E "s/^INSTALL_SH_CHART_VERSION=\"[^\"]*\"/INSTALL_SH_CHART_VERSION=\"$new\"/" "$(chart_install_sh "$name")"
    echo "bump: $name install.sh marker -> $new" >&2
  fi

  bumped+=("$name")
done

# Machine-readable output: the charts we actually bumped (empty if none).
((${#bumped[@]})) && printf '%s\n' "${bumped[@]}"
exit 0
