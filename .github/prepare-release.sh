#!/usr/bin/env bash
# Merge-time safety net for the "a chart's contents changed but version:
# (and, for charts that ship one, the install.sh marker) didn't move, or its
# docs went stale" contract.
#
# Why this exists: version-guard in lint-test.yml enforces the version:/marker
# half at PR time, and Renovate's renovate.json5 bumpVersions rule satisfies
# it automatically on Renovate PRs by moving version: and the install.sh
# marker together. But docs regeneration isn't part of that PR-time contract
# at all -- a Renovate PR that bumps version: itself still leaves the
# helm-docs README (Version/AppVersion badges, value tables) stale on main.
# And a human edit, or any path that only moves one of version:/marker, can
# still merge with the other left behind.
#
# This runs from release.yml on the push to main, the one path demonstrably
# guaranteed to run. For every chart changed in the push it:
#   1. patch-bumps version: if it hasn't already moved,
#   2. reconciles the install.sh marker to match version:, regardless of
#      which of the two moved it (this script, Renovate, or a human), and
#   3. regenerates the helm-docs README for every changed chart, independent
#      of whether this script bumped anything -- a chart whose version: was
#      already bumped on the PR still needs its docs regenerated here, since
#      nothing else does it.
# The chart-releaser step later in the same job then publishes the result.
#
# Idempotent: run over the same push twice and the second run finds version:
# and the marker already in sync and the docs already current, leaving the
# tree clean and printing nothing.
#
# Usage:
#   .github/prepare-release.sh [base-ref]   # default base: HEAD^ (prev push)
#
# Prints the names of the charts it changed (one per line) to stdout, but
# only once a commit is made; everything else goes to stderr.
#
# Requires: yq (v4+), helm-docs, git.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chart-paths.sh
source "$DIR/lib/chart-paths.sh"

BASE="${1:-HEAD^}"

# On a branch-creation push, event.before is all zeros and is not an ancestor of
# HEAD, so merge-base would fail. Fall back to HEAD^ in that case.
if [[ "$BASE" =~ ^0+$ ]] || ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "base: '$BASE' is not a resolvable commit, falling back to HEAD^" >&2
  BASE="HEAD^"
fi

changed="$(changed_charts "$BASE")"
if [[ -z "$changed" ]]; then
  echo "prepare-release: no changed charts" >&2
  exit 0
fi

# Bumps version: for every changed chart that has not already moved (e.g. by
# Renovate's bumpVersions rule on the PR branch).
"$DIR/bump-chart-versions.sh" "$BASE" >/dev/null

# Reconcile the install.sh marker for every changed chart, independent of
# whether THIS run or an earlier PR-time bump moved version: -- a chart whose
# version: moved without the marker (e.g. a hand edit) must still end up in
# sync, or action-helm-chart-repo's marker/Chart.yaml mismatch guard skips it.
for name in $changed; do
  current="$(chart_version "$name")"
  marker="$(install_sh_marker "$name")"
  if [[ -n "$marker" && "$marker" != "$current" ]]; then
    sed -i -E "s/^INSTALL_SH_CHART_VERSION=\"[^\"]*\"/INSTALL_SH_CHART_VERSION=\"$current\"/" "$(chart_install_sh "$name")"
    echo "reconcile: $name install.sh marker -> $current" >&2
  fi
done

# Regenerate docs for every changed chart, independent of whether this script
# bumped its version: above -- Renovate PRs already bump version: themselves,
# so by the time this runs there may be nothing left to bump, but the
# Version/AppVersion badges and value tables still need to catch up.
"$DIR/regen-chart-docs.sh" "$BASE"

if git diff --quiet -- charts/; then
  echo "prepare-release: no changes to commit" >&2
  exit 0
fi

# Commit on the push, not on a branch: this is the one path that is guaranteed
# to run, so the bump/marker/docs fix has to ride along with the merge rather
# than waiting for a PR-time push-back. The workflow pushes; committing here
# keeps all three atomic.
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add 'charts/**/Chart.yaml' 'charts/**/README.md' 'charts/**/install.sh'
git commit -m "chore: bump chart version(s) and regenerate docs for dependency update" >&2

printf '%s\n' "$changed"
