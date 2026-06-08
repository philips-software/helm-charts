# Hubble Flow Logs + SPIFFE-on-Collectors — Design

Date: 2026-06-08
Chart: `k8s-observability-monitoring`
Status: Approved (brainstorming) — pending implementation

## Summary

Add first-class support for shipping Cilium Hubble L7 flow/access logs to a destination,
folded into the existing upstream `alloy-logs` DaemonSet. This requires formalizing a way to
attach the SPIFFE `spiffe-helper` sidecar to upstream collectors (today only `custom-alloy`
gets it), which also retires a manual `collectorCommon` hack used in production.

Delivered in two parts:

1. **SPIFFE on upstream collectors** — declaratively attach `spiffe-helper` to named upstream
   collectors (`alloy-logs`, `alloy-receiver`, `alloy-metrics`).
2. **`hubbleFlowLogs` feature** — tail Cilium's flow export file on each node and ship it to a
   destination via a self-contained sub-pipeline with its own small batch.

## Motivation

- Pod-log collection (`podLogsViaLoki`) only tails `/var/log/pods`. Cilium Hubble L7 flows
  (HTTP/DNS/Kafka, `event_type` 129) are written by `cilium-agent` to a node-local file
  (`hubble-export-file-path`, default `/var/run/cilium/hubble/events.log`) — never to pod
  stdout — so they are invisible to the current pipeline.
- On SPIFFE clusters, the only way to get the `alloy-logs` DaemonSet to authenticate to a
  SPIFFE destination was a manual `collectorCommon.alloy.controller.{initContainers,
  extraContainers,volumes}` block injected out-of-band. That is fragile and undocumented.
- The chart is owned by us; the proper fix is to model both concerns in the chart rather than
  maintain a standalone DaemonSet or per-cluster hacks.

## Background / current chart behavior (verified)

- The chart renders an ArgoCD `Application` that deploys the upstream
  `grafana/k8s-monitoring` chart, which creates the `alloy-logs` DaemonSet (preset
  `filesystem-log-reader`), `alloy-receiver` Deployment, and (optionally) `alloy-metrics`.
- `config/k8s-monitoring-values.yaml.tpl` already has a per-collector passthrough
  (`collectors.<name>` → merged under the collector's `alloy:` key) and a global
  `collectorCommon` passthrough. Neither currently lets callers set `controller.*` or
  `extraConfig` on a specific collector cleanly.
- The upstream chart supports a per-collector `extraConfig` field (raw Alloy config, rendered
  with `tpl`) and exposes each destination's exporter as
  `otelcol.exporter.otlphttp.<sanitized-destination-name>.input` (and `otlp.` for gRPC).
  `alloy-logs` already wires the pod-logs destination, so its exporter component exists and can
  be referenced by an additional sub-pipeline.
- `custom-alloy` SPIFFE recipe (to be reused): `spiffe-helper-init` initContainer +
  `spiffe-helper` sidecar, a `csi.spiffe.io` workload-api volume, a `spiffe-jwt` emptyDir
  shared with the alloy container at `dir(spiffe.jwtPath)`, and the
  `<release>-custom-alloy-spiffe-helper` ConfigMap (`jwt_audience=<spiffe.audience>`,
  `jwt_svid_file_name=<spiffe.jwtPath>`).
- Why this works without SPIRE registration: the SPIRE catch-all ClusterSPIFFEID issues every
  pod an SVID, and gateways that trust the whole trust domain accept it. The chart only needs
  to produce the token file via the sidecar.

## Part 1 — SPIFFE auth on upstream collectors

### Values

```yaml
spiffe:
  enabled: false
  trustDomain: ""
  audience: ""
  jwtPath: /var/run/secrets/spiffe/jwt/token
  # NEW: upstream collectors that should receive the spiffe-helper sidecar so they can
  # authenticate to SPIFFE (bearerToken) destinations. Valid: alloy-logs, alloy-receiver,
  # alloy-metrics.
  collectors: []
  helper:
    image: ghcr.io/spiffe/spiffe-helper:0.10.0
    resources: { requests: { cpu: 1m, memory: 16Mi }, limits: { memory: 32Mi } }
```

### Helper template

New named template `k8s-observability-monitoring.spiffeCollectorValues` returning the Alloy
values fragment that attaches the sidecar:

```yaml
controller:
  initContainers:
    - name: spiffe-helper-init
      image: {{ spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf", "-daemon-mode=false"]
      resources: {{ spiffe.helper.resources }}
      volumeMounts:
        - { name: spiffe-workload-api, mountPath: /spiffe-workload-api, readOnly: true }
        - { name: spiffe-helper-config, mountPath: /etc/spiffe-helper, readOnly: true }
        - { name: spiffe-jwt, mountPath: dir(spiffe.jwtPath) }
  extraContainers:
    - name: spiffe-helper
      image: {{ spiffe.helper.image }}
      args: ["-config", "/etc/spiffe-helper/spiffe-helper.conf"]
      resources: {{ spiffe.helper.resources }}
      volumeMounts: <same three>
  volumes:
    extra:
      - { name: spiffe-workload-api, csi: { driver: csi.spiffe.io, readOnly: true } }
      - { name: spiffe-helper-config, configMap: { name: <release>-spiffe-helper } }
      - { name: spiffe-jwt, emptyDir: {} }
alloy:
  mounts:
    extra:
      - { name: spiffe-jwt, mountPath: dir(spiffe.jwtPath), readOnly: true }
```

### Config template change

In the `collectors:` loop, when a collector's name is in `spiffe.collectors`, deep-merge the
helper fragment into that collector's emitted `alloy:` block (alongside any existing
`collectors.<name>` overrides).

### ConfigMap generalization

Rename `custom-alloy-spiffe-helper-configmap.yaml` → `spiffe-helper-configmap.yaml`, ConfigMap
name `<release>-spiffe-helper`, rendered when:
`spiffe.enabled AND (customAlloy.enabled OR len(spiffe.collectors) > 0)`.
Update `custom-alloy-deployment.yaml` to reference the new ConfigMap name. (The content is
unchanged — same `agent_address`, `jwt_audience`, `jwt_svid_file_name`.)

## Part 2 — `hubbleFlowLogs` feature

### Values

```yaml
hubbleFlowLogs:
  enabled: false
  # Cilium hubble-export-file-path. The chart mounts the PARENT dir read-only and tails this
  # file. The chart does NOT configure Cilium — the operator must enable
  # hubble.export.{filePath, allowList: event_type 129} on the Cilium side.
  exportFilePath: /var/run/cilium/hubble/events.log
  # Destinations to ship flows to. Empty => same destinations as podLogsViaLoki.
  destinations: []
  # Keep OTLP batches under the gateway's gRPC receive limit (commonly 4 MB). Hubble flow JSON
  # is large (~4.5 KB/flow); 512 ~= 2.3 MB.
  batchMaxSize: 512
```

### Behavior (only touches `alloy-logs`)

1. **Host mount**: add `dir(exportFilePath)` as a read-only hostPath volume + mount to the
   alloy-logs collector, via the same per-collector `controller.volumes.extra` /
   `alloy.mounts.extra` passthrough Part 1 generalizes.

2. **Self-contained sub-pipeline** appended to the alloy-logs collector's upstream
   `extraConfig`:
   ```
   local.file_match "hubble"   → path_targets = [{ __path__ = exportFilePath, job = "cilium/hubble-flows" }]
   loki.source.file "hubble"   → forward_to = [loki.process.hubble.receiver]
   loki.process "hubble"       → stage.json { verdict, src_ns, dst_ns, flow_type } ; stage.structured_metadata
                               → forward_to = [otelcol.receiver.loki.hubble.receiver]
   otelcol.receiver.loki "hubble"      → logs = [otelcol.processor.transform.hubble.input]
   otelcol.processor.transform "hubble"→ set service.name=hubble-flows, service.namespace=cilium,
                                          k8s.cluster.name=<clusterName>
                                        → logs = [otelcol.processor.batch.hubble.input]
   otelcol.processor.batch "hubble"    → send_batch_max_size = batchMaxSize ; timeout 2s
                                        → logs = [otelcol.exporter.otlphttp.<dest>.input]
   ```
   The exporter referenced is the upstream-generated destination exporter. For each target
   destination, forward to `otelcol.exporter.otlphttp.<sanitized-dest>.input` (use `otlp.` when
   the destination protocol is gRPC). Multiple destinations → fan out the batch output list.

3. **Destination targeting**: `hubbleFlowLogs.destinations` empty → reuse the destinations
   resolved for `podLogsViaLoki`; else the named subset. SPIFFE auth is inherited because the
   destination's exporter (and the alloy-logs sidecar from Part 1) already handle it.

### Resulting Loki stream

`{service_name="hubble-flows", service_namespace="cilium"}` with full L7 HTTP records
(method, url, status, latency, src/dst pod, verdict). Labels `hubble-flows` / `cilium` are
fixed (not configurable) in this iteration.

## Validation / guardrails

In `templates/validation.yaml`:

- If `hubbleFlowLogs.enabled` and any resolved target destination uses
  `auth.type: bearerToken` (SPIFFE), require `alloy-logs` to be present in `spiffe.collectors`;
  otherwise `fail` with a message explaining the DaemonSet would crash-loop without the token
  file. (Mirrors production GOTCHA 2.)
- If `hubbleFlowLogs.enabled`, require at least one resolved destination with `logs.enabled`.

## Out of scope / non-goals

- Configuring Cilium itself (export path, allowlist, L7 CiliumNetworkPolicies). Documented as a
  prerequisite only.
- Making the pinned `service.name`/`service.namespace` labels configurable.
- Hubble metrics (Prometheus) — this is logs only.
- Dedicated standalone Hubble DaemonSet (rejected in favor of folding into alloy-logs).

## Testing

- `helm template` assertions:
  - With `spiffe.collectors: [alloy-logs]`: rendered Application valuesObject shows the
    spiffe-helper init+sidecar, csi volume, and jwt mount under `collectors.alloy-logs.alloy`.
  - With `hubbleFlowLogs.enabled`: collector `extraConfig` contains the `loki.source.file`
    targeting `exportFilePath`, the small `otelcol.processor.batch` (`send_batch_max_size`),
    and the correct `otelcol.exporter.otlphttp.<dest>.input` reference; the hostPath volume +
    mount for the parent dir are present.
  - Validation: SPIFFE destination + Hubble enabled + `alloy-logs` not in `spiffe.collectors`
    → template fails with the expected message.
  - ConfigMap renders when `customAlloy.enabled=false` but `spiffe.collectors` non-empty.
- Regenerate `README.md` via `helm-docs`.
- Bump `Chart.yaml` version `1.0.9 → 1.1.0` (additive, backward-compatible feature).

## Migration notes (for our dip-ce-k3s-eu cluster)

Once released and the chart is bumped on the cluster:
- Set `spiffe.collectors: [alloy-logs]` (replaces the manual `collectorCommon` spiffe-helper
  block — GOTCHA 2 hack) and `hubbleFlowLogs.enabled: true`.
- Delete the standalone `hubble-flowlogs-alloy.yaml` DaemonSet.
