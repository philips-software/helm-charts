#!/usr/bin/env bash
# Merge-time safety net for the "bumped a tag but not the chart version" contract.
#
# Why this exists: the contract is enforced at PR time by
# .github/workflows/chart-version-bump.yml (bumps version: on the PR branch) and
# by the version guard in lint-test.yml (fails the PR if it was missed). Both are
# pull_request-triggered, and those runs are not reliable in this repo: they have
# repeatedly been created, then sat unassigned for 6-17 hours and been
# auto-cancelled the moment the PR was merged, so the push-back never happened
# and the guard never reported. Dependency bumps therefore reached main with
# version: untouched, and chart-releaser (skip_existing: true) skipped the
# release: 34 such commits across 7 charts, invisible on the PR.
#
# This runs from release.yml instead -- on the push to main, where the workflow
# demonstrably does execute. For each chart changed in the push whose version:
# did not move, it patch-bumps version:, regenerates the helm-docs README, and
# commits. The chart-releaser step later in the same job then publishes the
# bumped chart normally.
#
# Idempotent: run over the same push twice and the second run finds the version
# already bumped, leaving the tree clean and printing nothing.
#
# Usage:
#   .github/prepare-release.sh [base-ref]   # default base: HEAD^ (prev push)
#
# Prints the names of the charts it bumped (one per line) to stdout; everything
# else goes to stderr.
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

# Bumps version: for every changed chart that has not already moved, then
# regenerates docs for the same set (order matters: docs read the new version).
bumped="$("$DIR/bump-chart-versions.sh" "$BASE")"
if [[ -z "$bumped" ]]; then
  echo "prepare-release: no chart version bump needed" >&2
  exit 0
fi

"$DIR/regen-chart-docs.sh" "$BASE"

# Commit on the push, not on a branch: this is the one path that is guaranteed
# to run, so the bump has to ride along with the merge rather than waiting for a
# PR-time push-back. The workflow pushes; committing here keeps the bump and the
# docs regeneration atomic.
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add 'charts/**/Chart.yaml' 'charts/**/README.md'
git commit -m "chore: bump chart version(s) and regenerate docs for dependency update" >&2

printf '%s\n' "$bumped"
