#!/usr/bin/env bash
# CI guard: fail if bumping a wrapped upstream chart would change an immutable
# StatefulSet spec field, which Argo CD cannot apply and cannot recover from.
#
# Why this exists
# ---------------
# Our *-bootstrap charts are thin wrappers that render an Argo CD Application
# pointing at an upstream chart, with the upstream version pinned in values.yaml
# and bumped automatically by Renovate. Because the pin looks like a plain OCI
# tag, Renovate will happily carry it across major versions -- loki went from
# 7.2.0 to 18.11.3 in a single PR.
#
# If such a bump changes an immutable StatefulSet field, the API server rejects
# the patch, Argo CD retries five times, gives up, and then will not retry again
# while the target revision is unchanged. The Application parks at
# OutOfSync/Healthy -- Healthy because the stale pods still run -- and the
# component silently stops receiving updates until a human notices. That is
# exactly how loki-ruler sat on loki 3.6.11 for ten days.
#
# `ct lint` / `ct install` cannot catch this: they install the NEW chart into an
# empty kind cluster, so there is no old object to conflict with. Catching an
# *upgrade* incompatibility requires rendering both versions and comparing. That
# is what this script does.
#
# How it works
# ------------
# For every chart changed relative to the base ref:
#   1. Render the wrapper chart at the merge-base and at HEAD.
#   2. From each rendering, pull out every Argo CD Application that targets a
#      Helm chart, along with its inline valuesObject. This is deliberately
#      generic: the wrapper itself tells us the upstream coordinates, so there
#      is no second place to keep a version-pin list in sync.
#   3. For each Application whose upstream chart version moved, pull and render
#      both upstream versions with their respective values.
#   4. Diff the immutable StatefulSet fields via lib/sts-immutable-diff.py.
#
# Usage:
#   .github/check-statefulset-immutables.sh [base-ref]   # default: origin/main
#
# Exit 0 if no immutable field would change, non-zero otherwise.
#
# Requires: helm (v3.8+, for OCI), yq (v4+), python3 + PyYAML, git.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/chart-paths.sh
source "$DIR/lib/chart-paths.sh"

BASE="${1:-origin/main}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
DIFF_TOOL="$DIR/lib/sts-immutable-diff.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Minimal values needed to get the wrapper charts past their validateConfig
# guards. These are render-only placeholders; they never reach a cluster.
RENDER_ARGS=(
  --set existingBucketName=ci-render-placeholder
  --set environmentConfig.resourcePrefix=ci
  --set environmentConfig.region=us-east-1
  --set environmentConfig.accountId=123456789012
)

# render_wrapper <chart-dir> <out-file>
#   Render a wrapper chart to a single manifest stream. A chart that cannot be
#   rendered even with the placeholders above is skipped by the caller.
render_wrapper() {
  local chart_dir="$1" out="$2" extra=()
  # Allow a chart to supply its own render-only values when the generic
  # placeholders are not enough.
  if [[ -f "$chart_dir/ci/immutable-check-values.yaml" ]]; then
    extra=(-f "$chart_dir/ci/immutable-check-values.yaml")
  fi
  helm template release "$chart_dir" -n argocd \
    "${RENDER_ARGS[@]}" "${extra[@]}" > "$out" 2>"$out.err"
}

# extract_apps <manifest-file> <out-jsonl>
#   Emit one JSON object per Argo CD Application that targets a Helm chart.
extract_apps() {
  yq -o=json -I=0 '
    select(.kind == "Application" and .spec.source.chart != null)
    | {
        "app":     .metadata.name,
        "repo":    .spec.source.repoURL,
        "chart":   .spec.source.chart,
        "version": .spec.source.targetRevision,
        "ns":      .spec.destination.namespace,
        "release": (.spec.source.helm.releaseName // .metadata.name),
        "values":  (.spec.source.helm.valuesObject // {})
      }' "$1" 2>/dev/null > "$2" || : > "$2"
}

# pull_chart <repo> <chart> <version> <dest-dir>
#   Fetch an upstream chart, handling both OCI registries and classic HTTP repos.
#   Echoes the path to the .tgz, or nothing on failure.
pull_chart() {
  local repo="$1" chart="$2" version="$3" dest="$4"
  mkdir -p "$dest"
  if [[ "$repo" == http://* || "$repo" == https://* ]]; then
    helm pull "$chart" --repo "$repo" --version "$version" -d "$dest" \
      >/dev/null 2>&1 || return 0
  else
    helm pull "oci://${repo#oci://}/$chart" --version "$version" -d "$dest" \
      >/dev/null 2>&1 || return 0
  fi
  ls "$dest"/*.tgz 2>/dev/null | head -1
}

violations=()
checked=0

for name in $(changed_charts "$BASE"); do
  chart_dir="$CHARTS_DIR/$name"
  [[ -d "$chart_dir" ]] || continue

  mergebase="$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"

  # Materialise the chart as it looked at the merge-base. A chart that did not
  # exist there is new, so there is no upgrade to validate.
  base_dir="$WORK/$name/base"
  mkdir -p "$base_dir"
  if ! git archive "$mergebase" "charts/$name" 2>/dev/null \
       | tar -x -C "$base_dir" --strip-components=2 2>/dev/null; then
    echo "skip: $name has no $BASE baseline (new chart)" >&2
    continue
  fi
  [[ -f "$base_dir/Chart.yaml" ]] || {
    echo "skip: $name has no $BASE baseline (new chart)" >&2
    continue
  }

  if ! render_wrapper "$base_dir" "$WORK/$name/base.yaml"; then
    echo "skip: $name does not render at $BASE" >&2
    continue
  fi
  if ! render_wrapper "$chart_dir" "$WORK/$name/head.yaml"; then
    echo "skip: $name does not render at HEAD" >&2
    continue
  fi

  extract_apps "$WORK/$name/base.yaml" "$WORK/$name/base.jsonl"
  extract_apps "$WORK/$name/head.yaml" "$WORK/$name/head.jsonl"

  while read -r head_app; do
    [[ -n "$head_app" ]] || continue
    app=$(jq -r .app <<<"$head_app")

    base_app="$(jq -c --arg a "$app" 'select(.app == $a)' "$WORK/$name/base.jsonl" | head -1)"
    [[ -n "$base_app" ]] || continue  # Application is new in this PR.

    old_version=$(jq -r .version <<<"$base_app")
    new_version=$(jq -r .version <<<"$head_app")
    repo=$(jq -r .repo <<<"$head_app")
    upstream=$(jq -r .chart <<<"$head_app")
    ns=$(jq -r .ns <<<"$head_app")
    release=$(jq -r .release <<<"$head_app")

    [[ "$old_version" != "$new_version" ]] || continue  # No upstream bump.

    old_tgz="$(pull_chart "$repo" "$upstream" "$old_version" "$WORK/$name/$app/old")"
    new_tgz="$(pull_chart "$repo" "$upstream" "$new_version" "$WORK/$name/$app/new")"
    if [[ -z "$old_tgz" || -z "$new_tgz" ]]; then
      echo "warn: $name/$app could not fetch $upstream $old_version -> $new_version; not checked" >&2
      continue
    fi

    jq .values <<<"$base_app" > "$WORK/$name/$app/old-values.json"
    jq .values <<<"$head_app" > "$WORK/$name/$app/new-values.json"

    helm template "$release" "$old_tgz" -n "$ns" \
      -f "$WORK/$name/$app/old-values.json" > "$WORK/$name/$app/old.yaml" 2>/dev/null
    helm template "$release" "$new_tgz" -n "$ns" \
      -f "$WORK/$name/$app/new-values.json" > "$WORK/$name/$app/new.yaml" 2>/dev/null
    if [[ ! -s "$WORK/$name/$app/old.yaml" || ! -s "$WORK/$name/$app/new.yaml" ]]; then
      echo "warn: $name/$app could not render $upstream; not checked" >&2
      continue
    fi

    checked=$((checked + 1))
    echo "checking: $name/$app ($upstream $old_version -> $new_version)" >&2
    if ! report="$(python3 "$DIFF_TOOL" \
                     "$WORK/$name/$app/old.yaml" "$WORK/$name/$app/new.yaml" \
                     --label "$name/$app")"; then
      violations+=("$report")
    elif [[ -n "$report" ]]; then
      echo "$report" >&2
    fi
  done < "$WORK/$name/head.jsonl"
done

if ((${#violations[@]})); then
  echo "::error::Upstream chart bump would change immutable StatefulSet fields." >&2
  printf '%s\n' "${violations[@]}" >&2
  cat >&2 <<'GUIDANCE'

Argo CD cannot apply these changes, and after five failed retries it will stop
retrying while the target revision is unchanged -- leaving the Application at
OutOfSync/Healthy with the old pods silently frozen.

To land this bump, the affected StatefulSets must be recreated. Either:

  * Let the statefulset-immutable-reconciler handle it (common-bootstrap).
    It watches for exactly this sync failure and orphan-deletes the offending
    StatefulSet so the next sync recreates it, adopting the running pods.
    Confirm it is enabled on the target clusters before merging.

  * Or recreate manually, per cluster, before merging:
        kubectl delete statefulset <name> -n <namespace> --cascade=orphan
        # then sync the Application; the new StatefulSet adopts the pods
    --cascade=orphan keeps the pods (and any PVCs) running, so there is no gap.

If a volumeClaimTemplate changed, read the upstream notes first: PVCs are NOT
resized by recreating the StatefulSet and may need separate expansion.
GUIDANCE
  exit 1
fi

echo "ok: no immutable StatefulSet changes across $checked upstream chart bump(s)" >&2
