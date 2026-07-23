# dex-issuer

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v2.45.1-dip.6](https://img.shields.io/badge/AppVersion-v2.45.1--dip.6-informational?style=flat-square)

Deploys [Dex](https://dexidp.io/) as an OpenID Connect issuer, together with its Postgres
storage, gRPC mTLS PKI, and the Crossplane `provider-dex` connector-management plane.

This is a wrapper chart. It does **not** define a `HelmApplication` — it assumes it is itself
provisioned by one — and it emits the underlying ArgoCD `Application`s and CRs.

## Issuer endpoint

The public issuer endpoint defaults to `https://<dex.httpRoute.host>.<clusterFqdn>`, e.g.
`https://issuer.${clusterFqdn}`. The host label is configurable via `dex.httpRoute.host`, and the
FQDN comes from `environmentConfig.clusterFqdn` (or `environmentConfig.customFqdn` when
`useCustomFqdn` is true).

## Environment injection

Cluster-specific details are injected through `environmentConfig`:

- `clusterFqdn` (**required**): the cluster's fully qualified domain name.
- `resourcePrefix` (**required**): prefixes account-global names (e.g. the Postgres identifier
  becomes `<resourcePrefix>-dex`) so they do not clash within a shared AWS account.
- `customFqdn` (optional): overrides `clusterFqdn` for the issuer when `useCustomFqdn` is true.

## Static clients and DCR

No static OAuth clients ship by default; add them via `dex.staticClients`. Dynamic Client
Registration (DCR) is enabled by default — real connectors and clients are created at runtime via
the Crossplane `provider-dex` gRPC API.

## Crossplane connector plane

When `provider.enabled` is true (default), the chart deploys the `provider-dex` Crossplane
provider (via the `crossplane-providers` chart) and its `ProviderConfig`s. Set
`provider.enabled=false` to deploy Dex on its own.

### gRPC mTLS

The Dex gRPC API can be secured with mTLS between Dex and `provider-dex`. This chart never creates
its own `ClusterIssuer` — that is a cluster-scoped resource, and a second chart creating one under
a common name (e.g. `crossplane-selfsigned-issuer`) causes ArgoCD `SharedResourceWarning`s and
ownership fights with whatever already owns it (typically the cluster bootstrap chart's own
Crossplane PKI).

Set `pki.existingClusterIssuer` to the name of an existing cluster-scoped `ClusterIssuer` to root
the mTLS CA chain (`crossplane-ca`, `dex-grpc-tls`, `provider-dex-client-tls`) in it. Leave it empty
to disable mTLS entirely: Dex then serves gRPC in plaintext and `provider-dex`'s `ProviderConfig`s
omit `spec.tls`.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argocd.namespace | string | `"argocd"` |  |
| argocd.project | string | `"default"` |  |
| database.allocatedStorage | int | `20` |  |
| database.barmanBackup.enabled | bool | `true` |  |
| database.barmanBackup.retentionDays | int | `7` |  |
| database.cnpg | bool | `true` |  |
| database.enableSnapshots | bool | `true` |  |
| database.engineVersion | string | `"18.1"` |  |
| database.size | string | `"xsmall"` |  |
| dex.allowedScopePrefixes[0] | string | `"hsp:iam:introspect"` |  |
| dex.dcr.enabled | bool | `true` |  |
| dex.expiry.idTokens | string | `"8h"` |  |
| dex.expiry.signingKeys | string | `"6h"` |  |
| dex.frontendIssuer | string | `"DIP Services"` |  |
| dex.httpRoute.enabled | bool | `true` |  |
| dex.httpRoute.host | string | `"issuer"` |  |
| dex.httpRoute.sharedGatewayName | string | `"platform"` |  |
| dex.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| dex.image.repository | string | `"ghcr.io/philips-forks/dex"` |  |
| dex.image.tag | string | `"v2.45.1-dip.6"` |  |
| dex.ingress.enabled | bool | `false` |  |
| dex.ingress.host | string | `"issuer"` |  |
| dex.ingress.ingressClassName | string | `"nginx"` |  |
| dex.logLevel | string | `"info"` |  |
| dex.replicas | int | `2` |  |
| dex.resources.limits.memory | string | `"128Mi"` |  |
| dex.resources.requests.cpu | string | `"10m"` |  |
| dex.resources.requests.memory | string | `"128Mi"` |  |
| dex.serviceMonitor.enabled | bool | `true` |  |
| dex.staticClients | list | `[]` |  |
| dex.staticClientsSecret.enabled | bool | `false` |  |
| dex.staticClientsSecret.name | string | `"dex-static-clients"` |  |
| dexChart.releaseName | string | `"dex"` |  |
| dexChart.repoURL | string | `"https://charts.dexidp.io"` |  |
| dexChart.version | string | `"0.24.1"` |  |
| environmentConfig.clusterFqdn | string | `""` |  |
| environmentConfig.customFqdn | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| pki.caDuration | string | `"87600h"` |  |
| pki.caNamespace | string | `"cert-manager"` |  |
| pki.caRenewBefore | string | `"8760h"` |  |
| pki.certDuration | string | `"8760h"` |  |
| pki.certRenewBefore | string | `"720h"` |  |
| pki.clientNamespace | string | `"crossplane-system"` |  |
| pki.existingClusterIssuer | string | `""` |  |
| provider.cascadeDelete | bool | `false` |  |
| provider.crossplaneProvidersVersion | string | `"0.0.35"` |  |
| provider.debug | bool | `true` |  |
| provider.enabled | bool | `true` |  |
| provider.providerConfigNamespaces | list | `[]` |  |
| provider.registry | string | `"xpkg.upbound.io/loafoe"` |  |
| provider.tag | string | `"v1.13.0"` |  |
| theme.enabled | bool | `true` |  |
| useCustomFqdn | bool | `false` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
