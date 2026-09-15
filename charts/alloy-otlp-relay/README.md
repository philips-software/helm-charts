# alloy-otlp-relay

Minimal Grafana Alloy deployment that:

- receives OTLP metrics over HTTP, in-cluster only (no Ingress/HTTPRoute)
- optionally filters metrics against an exact-name allow-list (`metricsFilter.allowList`); an
  empty list passes everything through
- forwards accepted metrics to a Mimir gateway, injecting an `X-Scope-OrgID` header
  (`mimir.tenantId`)

The receiver's default path (`receiver.http.metricsPath`) is `/otlp/v1/metrics`, not the
OTLP-standard `/v1/metrics` — this chart's primary use case is as an `otlp-gateway`
[caddy-mirror](https://github.com/loafoe/caddy-mirror) destination, and that plugin duplicates a
request at whatever path was already rewritten for the gateway's own primary upstream (Mimir's
native `/otlp/v1/metrics`), with no per-mirror path override. Set `receiver.http.metricsPath` to
`/v1/metrics` for direct, non-mirrored OTLP callers.

Runs as plain horizontal replicas behind a ClusterIP Service (no Alloy clustering) — the pipeline
has no scrape/discovery work to coordinate across peers, so each replica independently receives,
filters, and forwards.

## Install

```bash
helm upgrade --install alloy-otlp-relay charts/alloy-otlp-relay \
  --namespace alloy-long-term --create-namespace
```

## Key values

| Key | Description | Default |
|-----|-------------|---------|
| `replicas` | Number of Alloy replicas | `3` |
| `receiver.http.port` | OTLP/HTTP receiver port | `4318` |
| `receiver.http.metricsPath` | Path the receiver accepts metrics on | `/otlp/v1/metrics` |
| `metricsFilter.allowList` | Exact metric names to allow through; empty = pass all | `[]` |
| `mimir.url` | Base OTLP endpoint of the Mimir gateway | `http://mimir-gateway.mimir-system.svc.cluster.local/otlp` |
| `mimir.tenantId` | Value sent as `X-Scope-OrgID` | `long-term` |
