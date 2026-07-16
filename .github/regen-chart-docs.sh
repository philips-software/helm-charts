#!/usr/bin/env bash
# Regenerate helm-docs README.md for every chart changed since a base ref.
# Runs alongside bump-chart-versions.sh: a dependency PR changes appVersion /
# image tags / values, which drift the Version/AppVersion badges and value
# tables in the generated README. Scoped per-chart so unrelated stale docs
# elsewhere in the repo are NOT swept into the PR.
#
# Usage:
#   .github/regen-chart-docs.sh [base-ref]        # default base: origin/main
#
# Requires: helm-docs, git.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chart-paths.sh
source "$DIR/lib/chart-paths.sh"

BASE="${1:-origin/main}"

for name in $(changed_charts "$BASE"); do
  # Only charts that actually use helm-docs (have a template or existing README).
  if [[ -f "$CHARTS_DIR/$name/README.md.gotmpl" || -f "$CHARTS_DIR/$name/README.md" ]]; then
    echo "helm-docs: $name" >&2
    helm-docs --chart-search-root="charts/$name" >&2
  fi
done
