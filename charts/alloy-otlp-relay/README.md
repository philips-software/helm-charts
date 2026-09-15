# alloy-otlp-relay

Minimal Grafana Alloy deployment that:

- receives OTLP metrics over HTTP (`POST /v1/metrics`), in-cluster only (no Ingress/HTTPRoute)
- optionally filters metrics against an exact-name allow-list (`metricsFilter.allowList`); an
  empty list passes everything through
- forwards accepted metrics to a Mimir gateway, injecting an `X-Scope-OrgID` header
  (`mimir.tenantId`)

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
| `metricsFilter.allowList` | Exact metric names to allow through; empty = pass all | `[]` |
| `mimir.url` | Base OTLP endpoint of the Mimir gateway | `http://mimir-gateway.mimir-system.svc.cluster.local/otlp` |
| `mimir.tenantId` | Value sent as `X-Scope-OrgID` | `long-term` |
