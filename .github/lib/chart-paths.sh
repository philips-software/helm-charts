#!/usr/bin/env bash
# Shared helpers for mapping changed files to their owning chart and reading
# chart versions. Sourced by bump-chart-versions.sh (auto-bump on PR) and
# check-chart-versions.sh (CI guard). Keeping the logic here means the bumper
# and the guard can never disagree about what "the owning chart" is.
set -euo pipefail

# Absolute path to the charts/ directory in this repo.
CHARTS_DIR="$(git rev-parse --show-toplevel)/charts"

# owning_chart <path>
#   Given a repo-relative or absolute path, echo the chart directory name that
#   owns it (the first path segment under charts/), or nothing if the path is
#   not under charts/.
owning_chart() {
  local path="$1"
  # Normalise to repo-relative.
  path="${path#"$(git rev-parse --show-toplevel)"/}"
  case "$path" in
    charts/*)
      # charts/<name>/... -> <name>
      path="${path#charts/}"
      echo "${path%%/*}"
      ;;
    *) : ;;  # not under charts/, ignore
  esac
}

# chart_file <name>
#   Echo the absolute path to a chart's Chart.yaml.
chart_file() {
  echo "$CHARTS_DIR/$1/Chart.yaml"
}

# chart_version <name>
#   Echo the current version: field of a chart.
chart_version() {
  yq -r '.version' "$(chart_file "$1")"
}

# base_chart_version <name> <base-ref>
#   Echo a chart's version: as it was at the point this branch diverged from
#   <base-ref> (the merge-base), or empty if the chart did not exist there.
#   Uses the same merge-base as changed_charts so the two never disagree.
base_chart_version() {
  local name="$1" base="$2" mergebase
  mergebase="$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")"
  git show "$mergebase:charts/$name/Chart.yaml" 2>/dev/null | yq -r '.version' || echo ""
}

# changed_charts <base-ref>
#   Echo, one per line, the unique chart names that have any file changed since
#   this branch diverged from <base-ref>. Compares the merge-base against the
#   working tree, so both committed and uncommitted changes count. Excludes
#   deleted charts (Chart.yaml gone).
changed_charts() {
  local base="$1" f name mergebase
  mergebase="$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")"
  {
    for f in $(git diff --name-only "$mergebase" -- 'charts/**'); do
      name="$(owning_chart "$f")"
      [[ -n "$name" && -f "$(chart_file "$name")" ]] && echo "$name"
    done
  } | sort -u
}
