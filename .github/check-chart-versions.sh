#!/usr/bin/env bash
# CI guard: fail if a chart's contents changed relative to a base ref but its
# version: was NOT bumped. Complements bump-chart-versions.sh — the bumper runs
# on Renovate PRs, this guard catches human PRs (and any case the bumper missed)
# before they merge and silently no-op the release.
#
# Usage:
#   .github/check-chart-versions.sh [base-ref]    # default base: origin/main
#
# Exit 0 if every changed chart has a changed version:, non-zero otherwise.
#
# Requires: yq (v4+), git.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chart-paths.sh
source "$DIR/lib/chart-paths.sh"

BASE="${1:-origin/main}"

violations=()
for name in $(changed_charts "$BASE"); do
  current="$(chart_version "$name")"
  base_version="$(base_chart_version "$name" "$BASE")"

  if [[ -z "$base_version" ]]; then
    # New chart (no Chart.yaml at base) — nothing to bump against.
    echo "ok: $name is new" >&2
    continue
  fi

  if [[ "$current" == "$base_version" ]]; then
    violations+=("$name (still $current)")
  else
    echo "ok: $name $base_version -> $current" >&2
  fi
done

if ((${#violations[@]})); then
  echo "::error::The following charts changed but their version: was not bumped:" >&2
  printf '  - %s\n' "${violations[@]}" >&2
  echo "Bump version: in each chart's Chart.yaml (or run .github/bump-chart-versions.sh)." >&2
  exit 1
fi

echo "All changed charts have a bumped version." >&2
