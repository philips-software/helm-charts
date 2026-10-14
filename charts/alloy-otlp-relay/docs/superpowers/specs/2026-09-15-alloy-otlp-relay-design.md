# alloy-otlp-relay design

## Goal

Deploy a minimal Alloy instance to `ri-obs-ew2-ct` that:

- lives in its own namespace, `alloy-long-term`
- exposes an OTLP/HTTP endpoint (`/v1/metrics`), in-cluster only — no Ingress/HTTPRoute
- filters incoming metrics against a configurable exact-name allow-list (empty list = pass everything)
- forwards accepted metrics directly to the Mimir gateway in `mimir-system`, injecting
  `X-Scope-OrgID: long-term`

Success: an OTLP metrics payload POSTed to the relay's `/v1/metrics` is visible in Mimir under
the `long-term` tenant.

## Why a new chart, not an extension of `k8s-observability-monitoring`

`k8s-observability-monitoring` has two Alloy pipelines already:

- `applicationObservability` (upstream `alloy-receiver`, from the vendored `grafana/k8s-monitoring`
  chart) — has an OTLP receiver, but its `destinations` are passed straight through to the
  upstream chart's own schema, which has no confirmed support for custom headers or per-metric
  allow-list filtering.
- `customAlloy` — already has the exact header-injection pattern needed
  (`templates/custom-alloy-configmap.yaml:491-495`, `tenantId` → `X-Scope-OrgID`), but it's built
  around Prometheus *scraping* (kube-state-metrics/node-exporter/kubelet) and has no OTLP receiver.

Neither pipeline is shaped for "receive pushed OTLP metrics, filter, forward with a header" —
bolting that onto either means dragging in the upstream chart's alloy-operator and collector CRDs
for functionality this use case doesn't need. A small standalone chart mirroring the relevant
slice of `customAlloy` (Deployment + ConfigMap + Service, no RBAC since nothing is scraped) is a
better fit and stays backwards compatible with the existing chart (no changes to it at all).

## Deployment mechanism

The GitOps repo for this cluster fleet (`dip-oaas-ri-observability`) applies every stack under
`kustomize/observability-stack/` identically to all four `ri-obs-*` clusters — there's no
per-cluster include/exclude mechanism there. Since this must land on `ri-obs-ew2-ct` only, it's
deployed via direct `helm upgrade --install` against that cluster's context, not through the
shared GitOps repo. Not ArgoCD-managed — no selfHeal/drift protection. Revisit if/when this
becomes a permanent fixture and the platform gets per-cluster scoping.

## Chart layout

`charts/alloy-otlp-relay/`:

- `Chart.yaml` — `type: application`, versioned independently of other charts in this repo
- `values.yaml`
- `templates/_helpers.tpl`
- `templates/serviceaccount.yaml` — dedicated SA, no RBAC (receiver-only workload, no k8s API access)
- `templates/configmap.yaml` — renders `config.alloy`
- `templates/deployment.yaml`
- `templates/service.yaml` — ClusterIP, OTLP/HTTP port only

## Alloy pipeline

```
otelcol.receiver.otlp "default" {
  http { endpoint = "0.0.0.0:{{ .Values.receiver.http.port }}" }   // no grpc block: HTTP only
  output { metrics = [<next stage>] }
}

// only rendered when metricsFilter.allowList is non-empty
otelcol.processor.filter "metrics_allowlist" {
  error_mode = "ignore"
  metrics {
    metric = ["not (name == \"<name1>\" or name == \"<name2>\" ...)"]
  }
  output { metrics = [otelcol.exporter.otlphttp.mimir.input] }
}

otelcol.exporter.otlphttp "mimir" {
  client {
    endpoint = "{{ .Values.mimir.url }}"        // exporter appends /v1/metrics itself
    headers  = { "X-Scope-OrgID" = "{{ .Values.mimir.tenantId }}" }
    tls { insecure = true }                      // in-cluster HTTP, no TLS
  }
  retry_on_failure { enabled = true }
  sending_queue    { enabled = true }
}
```

When `metricsFilter.allowList` is empty, the receiver's output wires directly to the exporter and
the filter block is omitted — empty list passes everything through, per the goal.

Allow-list entries are exact metric names (equality checks), not regex — simpler to reason about
and matches the literal ask ("a list of metrics").

## values.yaml (key fields)

```yaml
replicas: 1

receiver:
  http:
    port: 4318

metricsFilter:
  # Exact metric names to allow through. Empty = pass everything.
  allowList: []

mimir:
  # Base OTLP endpoint; the otlphttp exporter appends /v1/metrics itself.
  url: "http://mimir-gateway.mimir-system.svc.cluster.local/otlp"
  tenantId: "long-term"

resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    memory: 256Mi   # no CPU limit: matches user preference and the cluster's own
                     # require-requests-limits Kyverno policy, which forbids a CPU limit key
```

Image: `docker.io/grafana/alloy:v1.19.2`, pinned inline in `templates/deployment.yaml` with a
Renovate comment directly above it (same convention as
`templates/custom-alloy-deployment.yaml:58-59` in `k8s-observability-monitoring`) — not exposed
as a value, consistent with how that chart pins the same image.

## Kyverno compliance (confirmed against live `ri-obs-ew2-ct` ClusterPolicies)

- `require-unique-service-account-per-workload`: dedicated ServiceAccount (`alloy-otlp-relay`),
  not `default`.
- `disallow-privilege-escalation` / `require-run-as-non-root-user`: container
  `securityContext.allowPrivilegeEscalation: false`, pod `securityContext.runAsNonRoot: true`.
- `disallow-latest-tag`: image tag pinned (`v1.19.2`).
- `require-requests-limits`: cpu+memory requests, memory-only limit (see above) — no ephemeral or
  init containers, so only the `containers` clause of the pattern applies.

## Verification plan

1. `helm template`/`helm lint` the new chart locally.
2. `helm upgrade --install alloy-otlp-relay charts/alloy-otlp-relay --namespace alloy-long-term
   --create-namespace` against the `ri-obs-ew2-ct` context; confirm the pod comes up healthy
   (Kyverno doesn't reject it, Alloy doesn't crash-loop on config parse).
3. Port-forward the Service; `curl -X POST localhost:<port>/v1/metrics` with a small OTLP JSON
   payload containing a couple of distinct metric names.
4. With `metricsFilter.allowList` empty, confirm both metrics reach Mimir under tenant
   `long-term` (query via query-frontend/querier with `X-Scope-OrgID: long-term`) and are absent
   under `anonymous`.
5. Set `metricsFilter.allowList` to one of the two metric names, `helm upgrade`, repeat step 3,
   and confirm only the allow-listed metric lands in Mimir.
