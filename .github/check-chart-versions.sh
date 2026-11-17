#!/usr/bin/env bash
# CI guard: fail if a chart's contents changed relative to a base ref but its
# version: was NOT bumped. Complements the push-time net in prepare-release.sh:
# Renovate bumps version: (and the install.sh marker, where one exists) itself
# via the renovate.json5 bumpVersions rule, so this guard is what makes a
# missed bump on a human PR visible before merge and silently no-op the
# release.
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
  elif [[ "$current" == "$base_version" ]]; then
    violations+=("$name (still $current)")
  else
    echo "ok: $name $base_version -> $current" >&2
  fi

  # A chart shipping an install.sh self-verify marker must keep it equal to
  # Chart.yaml's version, or action-helm-chart-repo silently skips publishing
  # it (caught here, at PR time, instead of as a skipped-chart annotation).
  marker="$(install_sh_marker "$name")"
  if [[ -n "$marker" && "$marker" != "$current" ]]; then
    violations+=("$name (install.sh INSTALL_SH_CHART_VERSION=$marker does not match Chart.yaml version: $current)")
  fi
done

if ((${#violations[@]})); then
  echo "::error::The following charts changed but their version: was not bumped:" >&2
  printf '  - %s\n' "${violations[@]}" >&2
  echo "Bump version: in each chart's Chart.yaml (or run .github/bump-chart-versions.sh)." >&2
  exit 1
fi

echo "All changed charts have a bumped version." >&2
