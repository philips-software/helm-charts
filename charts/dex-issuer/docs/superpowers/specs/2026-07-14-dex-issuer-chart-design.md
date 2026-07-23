# dex-issuer Helm chart — design

**Date:** 2026-07-14
**Status:** Approved (design decisions confirmed via brainstorming Q&A)

## Purpose

A wrapper Helm chart that provisions Dex (OpenID Connect issuer) and its Crossplane
connector-management plane, ported from the Kustomize base at
`dip-oaas-observability/kustomize/bootstrap/dex/base`. It follows the conventions of the
`grafana` chart in this repo (environmentConfig injection, resourcePrefix-ing, ArgoCD
`Application` wrapping of upstream charts, Crossplane provider wrapping via the
`crossplane-providers` chart).

The chart does **not** define a `HelmApplication` — it assumes it is itself provisioned by a
`HelmApplication`. All RI-specific details are removed and parameterized.

## Chart layout

```
charts/dex-issuer/
├── Chart.yaml                       # name: dex-issuer, version 0.1.0
├── values.yaml
├── README.md
├── config/
│   └── dex-values.yaml              # tpl'd valuesObject for the upstream dex chart
├── files/
│   └── theme/                       # styles.css, philips-logo.svg, logo.png
└── templates/
    ├── _helpers.tpl                 # name/labels, issuer fqdn/host/url, validateConfig
    ├── dex-helm.yaml                # ArgoCD Application → charts.dexidp.io/dex
    ├── database.yaml                # dip.io/v1alpha1 Postgres (resourcePrefix'd identifier)
    ├── httproute.yaml               # Gateway API HTTPRoute → issuer.${fqdn}
    ├── theme-configmap.yaml         # {{ if theme.enabled }} styles.css + logos
    ├── pki.yaml                     # {{ if provider.enabled }} self-signed CA + client cert
    ├── grpc-certificate.yaml        # dex gRPC server cert (cert-manager)
    ├── provider-dex.yaml            # {{ if provider.enabled }} App → crossplane-providers
    └── providerconfig-dex.yaml      # {{ if provider.enabled }} ProviderConfigs (multi-ns)
```

## 1. Environment injection & naming

- `environmentConfig.clusterFqdn` (required, domain-validated), `environmentConfig.resourcePrefix`
  (required), `environmentConfig.customFqdn` (optional). Same shape as the grafana chart.
- `useCustomFqdn: true` with a `dex-issuer.fqdn` helper: prefer `customFqdn` when set, else
  `clusterFqdn`.
- **Issuer URL** = `https://{dex.httpRoute.host}.{fqdn}`. Default host label `issuer`, giving
  `https://issuer.${clusterFqdn}`. The host part is configurable via `dex.httpRoute.host`.
- **resourcePrefix-ing** applies to account-global / clash-prone names. The Postgres CR uses
  `identifier: {{ resourcePrefix }}-dex` (the logical `databaseName` stays `dex`, matching the
  grafana chart). provider-dex uses gRPC mTLS (not AWS IRSA), so no IAM roles are created and no
  other account-global names exist.
- `dex-issuer.validateConfig` helper (mirrors grafana): fail fast on missing/invalid
  `clusterFqdn`, missing `resourcePrefix`, missing `dexChart.version`, missing `argocd.project`,
  and on `ingress`/`httpRoute` both enabled (mutually exclusive).

## 2. Dex deployment

`templates/dex-helm.yaml` emits an ArgoCD `Application`:
- `repoURL: https://charts.dexidp.io`, `chart: dex`,
  `targetRevision: {{ .Values.dexChart.version }}` (renovate-annotated, default `0.24.0`),
  `releaseName: dex`.
- `valuesObject` rendered from `config/dex-values.yaml` via `tpl`.

`config/dex-values.yaml` carries over from the base:
- `replicaCount`, `grpc` TLS config, postgres storage via env vars sourced from the
  `dex-postgres-connection` secret, `serviceMonitor.enabled`, `image` =
  `ghcr.io/philips-forks/dex` (renovate-annotated tag), memory-only `resources` (no CPU limit,
  per user preference), `topologySpreadConstraints`.
- Theme volumes/volumeMounts included only when `theme.enabled`.
- `envFrom: dex-static-clients` included only when `dex.staticClientsSecret.enabled`.

De-RI'd behaviour:
- `config.issuer` = `include "dex-issuer.url"`.
- `staticClients` from `.Values.dex.staticClients` (default `[]`).
- **Dynamic client registration (DCR) kept enabled** (`oauth2.dcr.enable: true`) — it is how
  clients/connectors are created at runtime.
- `frontend.issuer` configurable (default `"DIP Services"`).
- The placeholder `mockCallback` connector is retained so Dex boots on empty storage.

## 3. Crossplane connector plane (`provider.enabled`, default true)

- `pki.yaml`/`grpc-certificate.yaml` (mTLS, gated on `pki.existingClusterIssuer` being set — see
  addendum below): CA `Certificate` (namespace `cert-manager`) chained off the existing
  `ClusterIssuer` → CA `ClusterIssuer`; plus the `provider-dex-client-tls` client `Certificate` in
  `crossplane-system`.
- `grpc-certificate.yaml`: the Dex gRPC server `Certificate` (`dex-grpc-tls`) issued by the CA
  issuer, with in-cluster DNS SANs for the dex service.
- `provider-dex.yaml`: ArgoCD `Application` → `crossplane-providers` chart (grafana pattern),
  `package.registry: xpkg.upbound.io/loafoe`, `extraProviders: [{name: provider-dex, enabled,
  debug}]`, `cascadeDelete` toggle (default `false`, non-cascading — safe Crossplane teardown).
- `providerconfig-dex.yaml`: `ProviderConfig`s pointing at `dex.{ns}.svc.cluster.local:5557` over
  mTLS from the client cert. Namespaces configurable via `provider.providerConfigNamespaces`
  (default `[iam-dex, monitoring]`) plus the cluster-`default` ProviderConfig. RI `Client` CRs are
  **not** ported (they are consumer-specific).

## 4. Theme (`theme.enabled`, default true)

- `theme-configmap.yaml`: a `dex-theme` ConfigMap with `styles.css`, `philips-logo.svg`,
  `logo.png` read from `files/theme/`. The RI-specific `a[href^="/auth/..."]` hide-rules are
  stripped from `styles.css`. Mounted into Dex via the conditional volumes in
  `config/dex-values.yaml`.

## Out of scope

- No `HelmApplication` resource (chart is provisioned by one).
- No RI `Client` CRs, no RI static clients, no RI redirect URIs or issuer host.
- No AWS IRSA / IAM resources (provider-dex authenticates over gRPC mTLS).

## Addendum (2026-07-23): stop creating a shared ClusterIssuer

**Problem:** `pki.yaml` originally created its own `ClusterIssuer/crossplane-selfsigned-issuer`
unconditionally when `provider.enabled`. On dip-ce-k3s-eu, the cluster bootstrap chart
(`k8s-aws-bootstrap`) already owns a `ClusterIssuer` of that exact name for Crossplane's own
internal PKI (unrelated purpose). `ClusterIssuer` is cluster-scoped, so two ArgoCD Applications
managing the same name triggers a `SharedResourceWarning` and an ownership fight.

**Fix:** this chart no longer creates any `ClusterIssuer`. Instead:

- `pki.existingClusterIssuer` (default `""`) names an existing cluster-scoped `ClusterIssuer` to
  root the CA chain in. `crossplane-ca-issuer` (this chart's own, uniquely-named intermediate CA
  issuer) still gets created, but its `crossplane-ca` `Certificate` now chains off
  `pki.existingClusterIssuer` via `issuerRef` instead of a self-created selfSigned issuer.
- `dex-issuer.mtlsEnabled` helper (`_helpers.tpl`) = `provider.enabled && pki.existingClusterIssuer
  != ""`. `pki.yaml`, `grpc-certificate.yaml`, the `tls` block in `providerconfig-dex.yaml`'s
  `ProviderConfig`s, and the `grpc.tlsCert`/volumes in `config/dex-values.yaml` are all gated on
  this helper instead of bare `provider.enabled`.
- When `pki.existingClusterIssuer` is unset (default), mTLS is fully disabled: Dex serves gRPC
  in plaintext (`grpc.enabled: true`, no TLS files) and `ProviderConfig`s omit `spec.tls` —
  `provider-dex` then dials Dex over an insecure gRPC connection (supported natively by
  provider-dex's client, which uses insecure credentials when no TLS config is set).
- `crossplane-ca-issuer` and `provider-dex-client-tls` keep their existing names; only the
  colliding `crossplane-selfsigned-issuer` creation was removed. No renaming of already-live
  resources, to avoid unnecessary cert-manager churn on existing deployments.
