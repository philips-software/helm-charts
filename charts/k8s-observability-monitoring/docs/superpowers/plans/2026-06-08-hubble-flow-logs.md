# Hubble Flow Logs + SPIFFE-on-Collectors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add chart-managed Cilium Hubble L7 flow-log collection (folded into the upstream `alloy-logs` DaemonSet), plus a declarative way to attach the SPIFFE `spiffe-helper` sidecar to upstream collectors.

**Architecture:** The chart renders an ArgoCD `Application` that deploys the upstream `grafana/k8s-monitoring` chart. We extend `config/k8s-monitoring-values.yaml.tpl` so that (1) named upstream collectors in `spiffe.collectors` receive the spiffe-helper sidecar + CSI volume + JWT mount (reusing the existing `<release>-custom-alloy-spiffe-helper` ConfigMap), and (2) when `hubbleFlowLogs.enabled`, the `alloy-logs` collector gets a read-only hostPath mount of the Hubble export dir plus a self-contained Alloy `extraConfig` sub-pipeline that tails the flow file and ships it — with its own small batch — to the destination's existing OTLP exporter.

**Tech Stack:** Helm (Go templating, sprig), Grafana Alloy config language, ArgoCD Application, `helm template`/`ct lint`/`ct install` for testing, `helm-docs` for README.

**Spec:** `charts/k8s-observability-monitoring/docs/superpowers/specs/2026-06-08-hubble-flow-logs-design.md`

**Decisions locked in:**
- Keep the existing ConfigMap name `<release>-custom-alloy-spiffe-helper` (zero migration risk); only generalize its render *condition*. (Spec proposed a rename; we chose the no-rename option.)
- Fixed Loki labels `service.name=hubble-flows`, `service.namespace=cilium`.
- `hubbleFlowLogs.destinations: []` means "reuse `podLogsViaLoki` destinations".

**Testing note:** This repo has no `helm-unittest` plugin. Tests are render assertions run with `helm template ... | grep`/`yq`. Each test step gives the exact command and expected output. Work from the chart dir:
`cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/k8s-observability-monitoring`

**Test fixtures:** Create `ci/` value files used by render assertions (also picked up by `ct install`). Paths are relative to the chart dir.

---

## Task 1: Add `spiffe.collectors` + `hubbleFlowLogs` values

**Files:**
- Modify: `charts/k8s-observability-monitoring/values.yaml`

- [ ] **Step 1: Add `collectors` to the `spiffe` block**

In `values.yaml`, inside the `spiffe:` block (after `jwtPath: /var/run/secrets/spiffe/jwt/token`, before `helper:`), add:

```yaml
  # -- Upstream collectors that should receive the spiffe-helper sidecar so they can
  # authenticate to SPIFFE (bearerToken) destinations. Valid values: alloy-logs,
  # alloy-receiver, alloy-metrics. Replaces the manual collectorCommon sidecar injection.
  collectors: []
```

- [ ] **Step 2: Add the `hubbleFlowLogs` block**

In `values.yaml`, add a new top-level block immediately after the `podLogsViaLoki:` block (after its `excludeNamespaces: []` line):

```yaml
# -- Cilium Hubble L7 flow/access logs collection.
# Tails Cilium's flow export file on each node (via the alloy-logs DaemonSet) and ships it to
# a destination as OTLP logs. The chart does NOT configure Cilium: the operator must enable
# hubble.export on the Cilium side (file path below + allowlist event_type 129).
# Requires alloy-logs to have SPIFFE auth if a target destination uses bearerToken auth:
# add "alloy-logs" to spiffe.collectors.
hubbleFlowLogs:
  enabled: false
  # -- Cilium hubble-export-file-path. The chart mounts this file's parent dir read-only.
  exportFilePath: /var/run/cilium/hubble/events.log
  # -- Destinations to ship flows to. Empty = reuse the destinations resolved for podLogsViaLoki.
  destinations: []
  # -- Max OTLP batch size for flows. Hubble flow JSON is large (~4.5 KB/flow); keep batches
  # under the gateway's gRPC receive limit (commonly 4 MB). 512 ~= 2.3 MB.
  batchMaxSize: 512
```

- [ ] **Step 3: Verify the chart still renders**

Run: `cd charts/k8s-observability-monitoring && helm template t . --set clusterName=test >/dev/null && echo OK`
Expected: `OK` (no template errors)

- [ ] **Step 4: Commit**

```bash
git add charts/k8s-observability-monitoring/values.yaml
git commit -m "feat(k8s-observability-monitoring): add spiffe.collectors and hubbleFlowLogs values"
```

---

## Task 2: Add the spiffe-helper collector-values helper template

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/_helpers.tpl`

- [ ] **Step 1: Append the helper template**

Add to the end of `templates/_helpers.tpl`:

```
{{/*
Produce the Alloy values fragment that attaches the spiffe-helper sidecar to an upstream
collector, so it can authenticate to SPIFFE (bearerToken) destinations. Mirrors the sidecar
wiring used by custom-alloy. Reuses the <release>-custom-alloy-spiffe-helper ConfigMap.
Usage: {{ include "k8s-monitoring.spiffeCollectorValues" . }}  (pass the root context)
*/}}
{{- define "k8s-monitoring.spiffeCollectorValues" -}}
controller:
  initContainers:
    - name: spiffe-helper-init
      image: {{ .Values.spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf", "-daemon-mode=false"]
      resources:
        {{- toYaml .Values.spiffe.helper.resources | nindent 8 }}
      volumeMounts:
        - { name: spiffe-workload-api, mountPath: /spiffe-workload-api, readOnly: true }
        - { name: spiffe-helper-config, mountPath: /etc/spiffe-helper, readOnly: true }
        - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }} }
  extraContainers:
    - name: spiffe-helper
      image: {{ .Values.spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf"]
      resources:
        {{- toYaml .Values.spiffe.helper.resources | nindent 8 }}
      volumeMounts:
        - { name: spiffe-workload-api, mountPath: /spiffe-workload-api, readOnly: true }
        - { name: spiffe-helper-config, mountPath: /etc/spiffe-helper, readOnly: true }
        - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }} }
  volumes:
    extra:
      - { name: spiffe-workload-api, csi: { driver: csi.spiffe.io, readOnly: true } }
      - name: spiffe-helper-config
        configMap:
          name: {{ .Release.Name }}-custom-alloy-spiffe-helper
      - { name: spiffe-jwt, emptyDir: {} }
alloy:
  mounts:
    extra:
      - { name: spiffe-jwt, mountPath: {{ dir .Values.spiffe.jwtPath | quote }}, readOnly: true }
{{- end }}
```

- [ ] **Step 2: Verify it renders standalone**

Run: `cd charts/k8s-observability-monitoring && helm template t . --set clusterName=test --set spiffe.enabled=true --set spiffe.audience=otlp-gateway --set 'spiffe.collectors={alloy-logs}' >/dev/null && echo OK`
Expected: `OK` (the helper is not yet wired in, but must not break rendering)

- [ ] **Step 3: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/_helpers.tpl
git commit -m "feat(k8s-observability-monitoring): add spiffeCollectorValues helper template"
```

---

## Task 3: Wire `spiffe.collectors` into the collectors block

Introduce a single merge helper that combines per-collector overrides with the spiffe fragment, then rewire the three collectors to use it. (Task 6 extends this same helper for Hubble.)

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/_helpers.tpl`
- Modify: `charts/k8s-observability-monitoring/config/k8s-monitoring-values.yaml.tpl:62-85`
- Create: `charts/k8s-observability-monitoring/ci/spiffe-collectors-values.yaml`

- [ ] **Step 1: Add the merge helper to `_helpers.tpl`**

Append to `templates/_helpers.tpl`:

```
{{/*
Concatenate the list-valued "extra" keys (controller.volumes.extra and alloy.mounts.extra)
across a list of Alloy-values fragments, returning a single merged dict. mergeOverwrite REPLACES
lists, so we must concat these explicitly. Input: a list of dicts. Output: merged dict.
Usage: {{ include "k8s-monitoring.mergeAlloyFragments" (list $frag1 $frag2) | fromYaml ... }}
*/}}
{{- define "k8s-monitoring.mergeAlloyFragments" -}}
{{- $merged := dict -}}
{{- $vols := list -}}
{{- $mounts := list -}}
{{- range . -}}
  {{- $f := deepCopy . -}}
  {{- $vols = concat $vols (dig "controller" "volumes" "extra" (list) $f) -}}
  {{- $mounts = concat $mounts (dig "alloy" "mounts" "extra" (list) $f) -}}
  {{- $merged = mergeOverwrite $merged $f -}}
{{- end -}}
{{- if gt (len $vols) 0 -}}
  {{- $_ := set $merged "controller" (mergeOverwrite (dig "controller" (dict) $merged) (dict "volumes" (dict "extra" $vols))) -}}
{{- end -}}
{{- if gt (len $mounts) 0 -}}
  {{- $_ := set $merged "alloy" (mergeOverwrite (dig "alloy" (dict) $merged) (dict "mounts" (dict "extra" $mounts))) -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
Compute the merged Alloy values for a named upstream collector by collecting fragments
(per-collector overrides + spiffe-helper when listed in spiffe.collectors; Task 6 adds Hubble),
then concatenating their list-valued extras. Emits an "alloy:\n  <merged>" block, or nothing.
Usage: {{ include "k8s-monitoring.collectorAlloyBlock" (dict "ctx" . "name" "alloy-logs") }}
*/}}
{{- define "k8s-monitoring.collectorAlloyBlock" -}}
{{- $ctx := .ctx -}}
{{- $name := .name -}}
{{- $frags := list -}}
{{- $override := index $ctx.Values.collectors $name -}}
{{- if $override -}}
  {{- $frags = append $frags (deepCopy $override) -}}
{{- end -}}
{{- if and $ctx.Values.spiffe.enabled (has $name $ctx.Values.spiffe.collectors) -}}
  {{- $frags = append $frags (include "k8s-monitoring.spiffeCollectorValues" $ctx | fromYaml) -}}
{{- end -}}
{{- /* TASK 6 INSERTS THE HUBBLE FRAGMENT APPEND HERE */ -}}
{{- if gt (len $frags) 0 -}}
  {{- $merged := include "k8s-monitoring.mergeAlloyFragments" $frags | fromYaml -}}
alloy:
{{ toYaml $merged | indent 2 }}
{{- end -}}
{{- end }}
```

Note: `mergeOverwrite` mutates and REPLACES lists. `mergeAlloyFragments` works around that by
concatenating the two known list-valued keys (`controller.volumes.extra`, `alloy.mounts.extra`)
explicitly after the per-fragment merge, so spiffe volumes and Hubble volumes coexist.

- [ ] **Step 2: Rewire the `collectors:` block in the config tpl**

Replace `config/k8s-monitoring-values.yaml.tpl` lines 62-85 (the `collectors:` block, from `collectors:` through the `alloy-receiver` `{{- end }}`) with:

```
collectors:
  {{- $needsMetricsCollector := or (and .Values.prometheusOperatorObjects.enabled (not (and .Values.customAlloy .Values.customAlloy.enabled .Values.customAlloy.replaceUpstreamCollector))) .Values.clusterMetrics.enabled }}
  {{- if $needsMetricsCollector }}
  alloy-metrics:
    presets: [clustered, statefulset, medium]
    {{- include "k8s-monitoring.collectorAlloyBlock" (dict "ctx" . "name" "alloy-metrics") | nindent 4 }}
  {{- end }}
  alloy-logs:
    presets: [small, filesystem-log-reader, daemonset]
    {{- include "k8s-monitoring.collectorAlloyBlock" (dict "ctx" . "name" "alloy-logs") | nindent 4 }}
  {{- if .Values.applicationObservability.enabled }}
  alloy-receiver:
    presets: [small, deployment]
    {{- include "k8s-monitoring.collectorAlloyBlock" (dict "ctx" . "name" "alloy-receiver") | nindent 4 }}
  {{- end }}
```

- [ ] **Step 3: Create the CI/test values file**

Create `ci/spiffe-collectors-values.yaml`:

```yaml
clusterName: test-cluster
spiffe:
  enabled: true
  trustDomain: example.com
  audience: otlp-gateway
  collectors:
    - alloy-logs
destinations:
  gw:
    type: otlp
    url: https://gw.example.com
    protocol: http
    auth:
      type: bearerToken
      bearerTokenFile: /var/run/secrets/spiffe/jwt/token
    logs:
      enabled: true
podLogsViaLoki:
  enabled: true
```

- [ ] **Step 4: Verify the spiffe sidecar lands ONLY on alloy-logs**

Run:
```
cd charts/k8s-observability-monitoring
helm template t . -f ci/spiffe-collectors-values.yaml \
  | yq 'select(.kind=="Application") | .spec.source.helm.valuesObject.collectors'
```
Expected: `alloy-logs` has an `alloy.controller.extraContainers` entry named `spiffe-helper` and `alloy.controller.volumes.extra` includes `spiffe-workload-api`; `alloy-metrics`/`alloy-receiver` do NOT (here `alloy-receiver` is absent since applicationObservability is off).

- [ ] **Step 5: Confirm no spiffe sidecar when collector not listed**

Run:
```
helm template t . -f ci/spiffe-collectors-values.yaml --set 'spiffe.collectors=[]' \
  | yq 'select(.kind=="Application") | .spec.source.helm.valuesObject.collectors.alloy-logs'
```
Expected: `alloy-logs` has only `presets` (no `alloy:` block).

- [ ] **Step 6: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/_helpers.tpl charts/k8s-observability-monitoring/config/k8s-monitoring-values.yaml.tpl charts/k8s-observability-monitoring/ci/spiffe-collectors-values.yaml
git commit -m "feat(k8s-observability-monitoring): attach spiffe-helper to collectors via spiffe.collectors"
```

---

## Task 4: Generalize the spiffe-helper ConfigMap render condition

The ConfigMap must render when SPIFFE is used by collectors even if `customAlloy.enabled=false`.

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/custom-alloy-spiffe-helper-configmap.yaml:1`

- [ ] **Step 1: Broaden the guard**

In `templates/custom-alloy-spiffe-helper-configmap.yaml`, replace line 1:

```
{{- if and .Values.customAlloy.enabled .Values.spiffe.enabled }}
```

with:

```
{{- if and .Values.spiffe.enabled (or .Values.customAlloy.enabled (gt (len .Values.spiffe.collectors) 0)) }}
```

(ConfigMap name stays `{{ .Release.Name }}-custom-alloy-spiffe-helper` — no rename, no migration.)

- [ ] **Step 2: Verify the ConfigMap renders with customAlloy off but a spiffe collector set**

Run:
```
cd charts/k8s-observability-monitoring
helm template t . -f ci/spiffe-collectors-values.yaml \
  | yq 'select(.kind=="ConfigMap" and .metadata.name=="t-custom-alloy-spiffe-helper") | .metadata.name'
```
Expected: `t-custom-alloy-spiffe-helper`

- [ ] **Step 3: Verify it does NOT render when spiffe disabled**

Run:
```
helm template t . --set clusterName=test \
  | yq 'select(.kind=="ConfigMap" and .metadata.name=="t-custom-alloy-spiffe-helper") | .metadata.name'
```
Expected: empty output

- [ ] **Step 4: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/custom-alloy-spiffe-helper-configmap.yaml
git commit -m "feat(k8s-observability-monitoring): render spiffe-helper ConfigMap for spiffe.collectors"
```

---

## Task 5: Add the Hubble sub-pipeline + hostPath helper templates

Two helpers: one resolves the target destination component names; one renders the Alloy `extraConfig` sub-pipeline and the hostPath volume/mount fragment.

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/_helpers.tpl`

- [ ] **Step 1: Add a helper that resolves Hubble destinations**

Append to `templates/_helpers.tpl`:

```
{{/*
Resolve the list of destination NAMES that Hubble flows should be shipped to.
hubbleFlowLogs.destinations if non-empty, else podLogsViaLoki.destinations if non-empty,
else all destinations whose logs.enabled is true.
Usage: {{ include "k8s-monitoring.hubbleDestinations" . }}  -> space-separated names
*/}}
{{- define "k8s-monitoring.hubbleDestinations" -}}
{{- $names := list -}}
{{- if gt (len .Values.hubbleFlowLogs.destinations) 0 -}}
  {{- $names = .Values.hubbleFlowLogs.destinations -}}
{{- else if gt (len .Values.podLogsViaLoki.destinations) 0 -}}
  {{- $names = .Values.podLogsViaLoki.destinations -}}
{{- else -}}
  {{- range $name, $dest := .Values.destinations -}}
    {{- if and (hasKey $dest "logs") $dest.logs.enabled -}}
      {{- $names = append $names $name -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $names | join " " -}}
{{- end }}
```

- [ ] **Step 2: Add the sub-pipeline `extraConfig` helper**

Append to `templates/_helpers.tpl`. The exporter component name uses the upstream chart's
`alloy_name` sanitization (lowercase alnum/`_`); destination names are already DNS-ish so we
replicate it with a sprig regex to be safe.

```
{{/*
Render the Alloy extraConfig sub-pipeline that tails the Hubble export file and ships flows to
each resolved destination's OTLP exporter, with its own small batch. Returns a raw Alloy
config string (to be placed under collectors.alloy-logs.alloy.extraConfig).
Usage: {{ include "k8s-monitoring.hubbleExtraConfig" . }}
*/}}
{{- define "k8s-monitoring.hubbleExtraConfig" -}}
{{- $destNames := splitList " " (include "k8s-monitoring.hubbleDestinations" .) -}}
{{- $exporters := list -}}
{{- range $destNames -}}
  {{- $san := regexReplaceAll "[^a-zA-Z0-9_]" . "_" -}}
  {{- $exporters = append $exporters (printf "otelcol.exporter.otlphttp.%s.input" $san) -}}
{{- end -}}
local.file_match "hubble" {
  path_targets = [{
    __path__ = {{ .Values.hubbleFlowLogs.exportFilePath | quote }},
    job      = "cilium/hubble-flows",
  }]
}
loki.source.file "hubble" {
  targets    = local.file_match.hubble.targets
  forward_to = [loki.process.hubble.receiver]
}
loki.process "hubble" {
  stage.json {
    expressions = {
      verdict   = "flow.verdict",
      flow_type = "flow.Type",
      src_ns    = "flow.source.namespace",
      dst_ns    = "flow.destination.namespace",
    }
  }
  stage.structured_metadata {
    values = { verdict = "", flow_type = "", src_ns = "", dst_ns = "" }
  }
  forward_to = [otelcol.receiver.loki.hubble.receiver]
}
otelcol.receiver.loki "hubble" {
  output { logs = [otelcol.processor.transform.hubble.input] }
}
otelcol.processor.transform "hubble" {
  error_mode = "ignore"
  log_statements {
    context = "resource"
    statements = [
      `set(attributes["service.name"], "hubble-flows")`,
      `set(attributes["service.namespace"], "cilium")`,
      `set(attributes["k8s.cluster.name"], {{ .Values.clusterName | quote }})`,
    ]
  }
  output { logs = [otelcol.processor.batch.hubble.input] }
}
otelcol.processor.batch "hubble" {
  timeout             = "2s"
  send_batch_size     = {{ .Values.hubbleFlowLogs.batchMaxSize }}
  send_batch_max_size = {{ .Values.hubbleFlowLogs.batchMaxSize }}
  output {
    logs = [{{ $exporters | join ", " }}]
  }
}
{{- end }}
```

Note the inner `{{ .Values.clusterName | quote }}` is rendered by the upstream chart's `tpl`
call on `extraConfig`. The backtick OTTL statements are literal Alloy; only the `set(...
cluster.name ...)` line interpolates. Because the whole block is rendered by THIS chart first
(it is plain text in our config tpl), `.Values.clusterName` resolves here at our render time —
acceptable since clusterName is static.

- [ ] **Step 3: Add the hostPath fragment helper**

Append to `templates/_helpers.tpl`:

```
{{/*
Alloy values fragment giving alloy-logs a read-only hostPath mount of the Hubble export dir.
Usage: {{ include "k8s-monitoring.hubbleMountValues" . }}
*/}}
{{- define "k8s-monitoring.hubbleMountValues" -}}
{{- $dir := dir .Values.hubbleFlowLogs.exportFilePath -}}
controller:
  volumes:
    extra:
      - name: hubble-export
        hostPath:
          path: {{ $dir | quote }}
          type: Directory
alloy:
  extraConfig: |-
{{ include "k8s-monitoring.hubbleExtraConfig" . | indent 4 }}
  mounts:
    extra:
      - name: hubble-export
        mountPath: {{ $dir | quote }}
        readOnly: true
{{- end }}
```

- [ ] **Step 4: Verify all helpers parse**

Run: `cd charts/k8s-observability-monitoring && helm template t . --set clusterName=test --set hubbleFlowLogs.enabled=true >/dev/null && echo OK`
Expected: `OK` (helpers defined but not yet wired into a collector — must not break)

- [ ] **Step 5: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/_helpers.tpl
git commit -m "feat(k8s-observability-monitoring): add Hubble sub-pipeline + mount helpers"
```

---

## Task 6: Merge the Hubble fragment into alloy-logs

Extend the `collectorAlloyBlock` helper (from Task 3) so the alloy-logs collector also gets the Hubble mount + extraConfig when `hubbleFlowLogs.enabled`.

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/_helpers.tpl` (the `collectorAlloyBlock` define)
- Create: `charts/k8s-observability-monitoring/ci/hubble-values.yaml`

- [ ] **Step 1: Extend `collectorAlloyBlock` to append the Hubble fragment**

In `templates/_helpers.tpl`, find the marker line inside the `k8s-monitoring.collectorAlloyBlock`
define:

```
{{- /* TASK 6 INSERTS THE HUBBLE FRAGMENT APPEND HERE */ -}}
```

Replace that single marker line with:

```
{{- if and (eq $name "alloy-logs") $ctx.Values.hubbleFlowLogs.enabled -}}
  {{- $frags = append $frags (include "k8s-monitoring.hubbleMountValues" $ctx | fromYaml) -}}
{{- end -}}
```

That is the ONLY change needed. List concatenation of `controller.volumes.extra` and
`alloy.mounts.extra` across the spiffe and Hubble fragments is already handled by
`mergeAlloyFragments` (Task 3), so the spiffe volumes and Hubble volume coexist automatically.
`extraConfig` is a multi-line string key unique to the Hubble fragment; `fromYaml`/`toYaml`
round-trips it as a block scalar correctly.

- [ ] **Step 2: Create `ci/hubble-values.yaml`**

```yaml
clusterName: test-cluster
spiffe:
  enabled: true
  trustDomain: example.com
  audience: otlp-gateway
  collectors:
    - alloy-logs
destinations:
  gw:
    type: otlp
    url: https://gw.example.com
    protocol: http
    auth:
      type: bearerToken
      bearerTokenFile: /var/run/secrets/spiffe/jwt/token
    logs:
      enabled: true
podLogsViaLoki:
  enabled: true
hubbleFlowLogs:
  enabled: true
  batchMaxSize: 512
```

- [ ] **Step 3: Verify alloy-logs has BOTH spiffe sidecar AND hubble mount + pipeline**

Run:
```
cd charts/k8s-observability-monitoring
helm template t . -f ci/hubble-values.yaml \
  | yq 'select(.kind=="Application") | .spec.source.helm.valuesObject.collectors.alloy-logs.alloy'
```
Expected, ALL present:
- `controller.extraContainers[].name == spiffe-helper`
- `controller.volumes.extra` contains BOTH `spiffe-workload-api` AND `hubble-export`
- `mounts.extra` contains BOTH `spiffe-jwt` AND `hubble-export`
- `extraConfig` contains `local.file_match "hubble"`, `send_batch_size = 512`, and `otelcol.exporter.otlphttp.gw.input`

- [ ] **Step 4: Verify exporter name matches the destination**

Run:
```
helm template t . -f ci/hubble-values.yaml \
  | yq 'select(.kind=="Application") | .spec.source.helm.valuesObject.collectors.alloy-logs.alloy.extraConfig' \
  | grep -c 'otelcol.exporter.otlphttp.gw.input'
```
Expected: `1` (or more)

- [ ] **Step 5: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/_helpers.tpl charts/k8s-observability-monitoring/ci/hubble-values.yaml
git commit -m "feat(k8s-observability-monitoring): ship Hubble flows via alloy-logs collector"
```

---

## Task 7: Add validation guardrails

Fail the render early with a clear message when Hubble is enabled but the required SPIFFE wiring is missing, or no logs destination is resolvable.

**Files:**
- Modify: `charts/k8s-observability-monitoring/templates/_helpers.tpl` (new validate define)
- Modify: `charts/k8s-observability-monitoring/templates/validation.yaml`

- [ ] **Step 1: Add the validation helper**

Append to `templates/_helpers.tpl`:

```
{{/*
Validate Hubble flow-log configuration.
Usage: {{ include "k8s-monitoring.validateHubbleFlowLogs" . }}
*/}}
{{- define "k8s-monitoring.validateHubbleFlowLogs" -}}
{{- if .Values.hubbleFlowLogs.enabled -}}
  {{- $destNames := splitList " " (include "k8s-monitoring.hubbleDestinations" .) -}}
  {{- if or (eq (len $destNames) 0) (eq (join "" $destNames) "") -}}
    {{- fail "hubbleFlowLogs.enabled is true but no logs-enabled destination could be resolved. Set hubbleFlowLogs.destinations, or podLogsViaLoki.destinations, or enable logs on a destination." -}}
  {{- end -}}
  {{- range $destNames -}}
    {{- $dest := index $.Values.destinations . -}}
    {{- if and $dest $dest.auth (eq (dig "auth" "type" "" $dest) "bearerToken") -}}
      {{- if not (and $.Values.spiffe.enabled (has "alloy-logs" $.Values.spiffe.collectors)) -}}
        {{- fail (printf "hubbleFlowLogs targets destination %q which uses SPIFFE bearerToken auth, but alloy-logs has no spiffe-helper sidecar. Add \"alloy-logs\" to spiffe.collectors (and set spiffe.enabled=true), otherwise the alloy-logs DaemonSet will crash-loop with a missing token file." .) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
```

- [ ] **Step 2: Invoke it from `validation.yaml`**

Append to `templates/validation.yaml`:

```
{{ include "k8s-monitoring.validateHubbleFlowLogs" . }}
```

- [ ] **Step 3: Verify the guardrail fires (SPIFFE dest, alloy-logs not in collectors)**

Run:
```
cd charts/k8s-observability-monitoring
helm template t . -f ci/hubble-values.yaml --set 'spiffe.collectors=[]' 2>&1 | grep -o "crash-loop with a missing token file" | head -1
```
Expected: `crash-loop with a missing token file`

- [ ] **Step 4: Verify happy path still renders**

Run: `helm template t . -f ci/hubble-values.yaml >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 5: Verify non-SPIFFE Hubble dest does NOT require spiffe.collectors**

Create `ci/hubble-basic-auth-values.yaml`:

```yaml
clusterName: test-cluster
destinations:
  gw:
    type: otlp
    url: https://gw.example.com
    protocol: http
    auth:
      type: basic
      usernameKey: username
      passwordKey: apiKey
    secret:
      create: false
      name: gw-creds
    logs:
      enabled: true
podLogsViaLoki:
  enabled: true
hubbleFlowLogs:
  enabled: true
```

Run: `helm template t . -f ci/hubble-basic-auth-values.yaml >/dev/null && echo OK`
Expected: `OK` (no SPIFFE requirement triggered)

- [ ] **Step 6: Commit**

```bash
git add charts/k8s-observability-monitoring/templates/_helpers.tpl charts/k8s-observability-monitoring/templates/validation.yaml charts/k8s-observability-monitoring/ci/hubble-basic-auth-values.yaml
git commit -m "feat(k8s-observability-monitoring): validate Hubble flow-log SPIFFE prerequisites"
```

---

## Task 8: Bump chart version, regenerate README, full lint

**Files:**
- Modify: `charts/k8s-observability-monitoring/Chart.yaml:3`
- Modify: `charts/k8s-observability-monitoring/README.md` (generated)

- [ ] **Step 1: Bump the chart version**

In `Chart.yaml`, change `version: 1.0.9` to `version: 1.1.0` (additive, backward-compatible).

- [ ] **Step 2: Regenerate the README**

Run: `cd charts/k8s-observability-monitoring && helm-docs --chart-search-root .`
Expected: `README.md` updated; `git diff --stat README.md` shows changes for the new values.

- [ ] **Step 3: Confirm new values are documented**

Run: `grep -E "hubbleFlowLogs|spiffe.collectors" charts/k8s-observability-monitoring/README.md | head`
Expected: rows for `hubbleFlowLogs.*` and `spiffe.collectors` present.

- [ ] **Step 4: Lint the chart**

Run: `cd /Users/andy/DEV/Philips/philips-software/helm-charts && helm lint charts/k8s-observability-monitoring --set clusterName=test`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Full render smoke test across all CI fixtures**

Run:
```
cd charts/k8s-observability-monitoring
for f in ci/*.yaml; do echo "== $f =="; helm template t . -f "$f" >/dev/null && echo OK || echo FAIL; done
```
Expected: every fixture prints `OK`.

- [ ] **Step 6: Commit**

```bash
git add charts/k8s-observability-monitoring/Chart.yaml charts/k8s-observability-monitoring/README.md
git commit -m "chore(k8s-observability-monitoring): bump to 1.1.0, regenerate README"
```

---

## Post-implementation (separate, on the cluster — NOT part of this plan's commits)

Once the chart is released/available to the dip-ce-k3s-eu cluster:
1. In `~/DEV/Personal/k3s/dip-ce-k3s-eu-monitoring-values.yaml`: remove the manual
   `collectorCommon.alloy.controller.{initContainers,extraContainers,volumes}` spiffe block;
   add `spiffe.collectors: [alloy-logs]` and `hubbleFlowLogs.enabled: true`.
2. `helm upgrade` the release.
3. Verify `{service_name="hubble-flows"}` in rpi Loki, then `kubectl delete -f hubble-flowlogs-alloy.yaml`.
4. Update `~/DEV/Personal/k3s/CLAUDE.md` to point at the chart feature instead of the standalone manifest.
