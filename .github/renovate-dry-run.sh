#!/usr/bin/env bash
# Test Renovate locally against this repo without opening PRs.
#
# Detects which dependency updates Renovate WOULD create, using the live
# .github/renovate.json5 config and the working tree as-is. Nothing is pushed.
#
# Usage:
#   .github/renovate-dry-run.sh                # full dry-run, all deps
#   .github/renovate-dry-run.sh caddy-token    # filter output to one dep
#
# Requires: the `renovate` CLI (npm i -g renovate, or `brew install renovate`)
# and a GitHub token (sourced from `gh auth token`) for github-* datasources.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

export RENOVATE_TOKEN="${RENOVATE_TOKEN:-$(gh auth token)}"
filter="${1:-}"

# --platform=local reads the current checkout; --dry-run=full does lookups but
# never creates branches/PRs. LOG_LEVEL=debug exposes per-dep newVersion info.
if [[ -n "$filter" ]]; then
  LOG_LEVEL=debug renovate --platform=local --dry-run=full 2>&1 \
    | grep -A12 "\"depName\": .*${filter}" \
    | grep -iE "depName|newVersion|newValue|updateType|currentValue" || {
      echo "No update detected for '${filter}' (or dep not found)."
      exit 1
    }
else
  renovate --platform=local --dry-run=full 2>&1 | grep -iE "flattened updates|Dependency extraction complete" -A4
fi
