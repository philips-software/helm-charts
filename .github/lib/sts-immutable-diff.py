#!/usr/bin/env python3
"""Diff the immutable StatefulSet spec fields between two rendered manifest sets.

The Kubernetes API server only permits updates to these StatefulSet spec fields:

    replicas, ordinals, template, updateStrategy, revisionHistoryLimit,
    persistentVolumeClaimRetentionPolicy, minReadySeconds

Changing anything else is rejected with:

    StatefulSet.apps "<name>" is invalid: spec: Forbidden: updates to
    statefulset spec for fields other than ... are forbidden

Under plain `helm upgrade` that surfaces immediately as a failed release. Under
Argo CD it is far worse: the sync fails, Argo CD retries five times, gives up,
and then will NOT retry again for an unchanged target revision. The affected
workload silently keeps running the OLD pod spec while the Application sits at
OutOfSync/Healthy -- "Healthy" because the stale pods are perfectly fine. That
is how loki-ruler stayed pinned to loki 3.6.11 for ten days while the rest of
the stack moved to 3.7.8.

Upstream charts sometimes ship a migration path for this (the Loki chart has
`statefulSetRecreateJob`), but those are gated on Helm's `lookup`, which returns
nothing under `helm template`. Argo CD renders with `helm template`, so such
jobs are never emitted for us. See loki/README.md: "`lookup` needs a live
cluster; `helm template` / dry-run will not emit it."

So the break has to be caught before merge. This script is the comparison
engine: given the upstream manifests rendered at the OLD pin and at the NEW pin,
it reports every StatefulSet whose immutable fields would change.

Usage:
    sts-immutable-diff.py <old-rendered.yaml> <new-rendered.yaml> [--label TEXT]

Exit 0 when no immutable field changes, 1 when at least one does.
"""

from __future__ import annotations

import argparse
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("sts-immutable-diff.py requires PyYAML (pip install pyyaml)")

# Fields the API server lets you mutate on an existing StatefulSet. Anything
# else under .spec is immutable and requires delete + recreate.
MUTABLE_SPEC_FIELDS = frozenset(
    {
        "replicas",
        "ordinals",
        "template",
        "updateStrategy",
        "revisionHistoryLimit",
        "persistentVolumeClaimRetentionPolicy",
        "minReadySeconds",
    }
)

# Immutable fields the API server defaults when a manifest omits them. If one
# chart version leaves the field out and the next sets it explicitly to the same
# default, the live object already holds that value and the apply is a no-op --
# so normalise before comparing, or we report drift that cannot actually fail.
IMMUTABLE_DEFAULTS = {
    "podManagementPolicy": "OrderedReady",
}


def immutable_spec(spec: dict) -> dict:
    """Project a StatefulSet .spec down to just its immutable fields."""
    out = {
        key: value
        for key, value in spec.items()
        if key not in MUTABLE_SPEC_FIELDS
    }
    for key, default in IMMUTABLE_DEFAULTS.items():
        out[key] = spec.get(key) or default
    return out


def load_statefulsets(path: str) -> dict[str, dict]:
    """Map StatefulSet name -> immutable spec projection, from a manifest file."""
    found: dict[str, dict] = {}
    with open(path) as handle:
        for doc in yaml.safe_load_all(handle):
            if not doc or doc.get("kind") != "StatefulSet":
                continue
            name = doc.get("metadata", {}).get("name")
            if not name:
                continue
            found[name] = immutable_spec(doc.get("spec") or {})
    return found


def describe(value: object) -> str:
    """Render a field value compactly enough to read in CI log output."""
    if isinstance(value, (dict, list)):
        return yaml.safe_dump(value, default_flow_style=True).strip()
    return repr(value)


def diff_statefulset(old: dict, new: dict) -> list[tuple[str, object, object]]:
    """Return (field, old, new) for each immutable field that differs."""
    changes = []
    for field in sorted(set(old) | set(new)):
        before, after = old.get(field), new.get(field)
        if before != after:
            changes.append((field, before, after))
    return changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old", help="manifests rendered at the OLD chart pin")
    parser.add_argument("new", help="manifests rendered at the NEW chart pin")
    parser.add_argument("--label", default="", help="context shown in output")
    parser.add_argument(
        "--ignore-fields",
        default="",
        help="comma-separated .spec fields Argo CD is told to ignore for "
        "StatefulSets via the Application's ignoreDifferences. A change to "
        "such a field is never applied, so it cannot wedge the sync.",
    )
    args = parser.parse_args()

    ignored = {f for f in (x.strip() for x in args.ignore_fields.split(",")) if f}

    old_sets = load_statefulsets(args.old)
    new_sets = load_statefulsets(args.new)

    prefix = f"{args.label}: " if args.label else ""
    breaking = False

    for name in sorted(set(old_sets) & set(new_sets)):
        changes = diff_statefulset(old_sets[name], new_sets[name])
        skipped = [c for c in changes if c[0] in ignored]
        changes = [c for c in changes if c[0] not in ignored]

        for field, _, _ in skipped:
            print(f"{prefix}note: StatefulSet/{name} .spec.{field} changed, but "
                  "the Application ignores it (ignoreDifferences), so Argo CD "
                  "never applies it")

        if not changes:
            continue
        breaking = True
        print(f"{prefix}StatefulSet/{name} changes immutable spec fields:")
        for field, before, after in changes:
            print(f"    .spec.{field}")
            print(f"        old: {describe(before)}")
            print(f"        new: {describe(after)}")

    # A StatefulSet that disappears from the rendered set is a different
    # problem (prune, rename, component disabled) -- report it as information
    # so a rename is not mistaken for a clean upgrade, but do not fail on it.
    for name in sorted(set(old_sets) - set(new_sets)):
        print(f"{prefix}note: StatefulSet/{name} is no longer rendered "
              "(renamed, disabled, or removed upstream)")

    return 1 if breaking else 0


if __name__ == "__main__":
    sys.exit(main())
