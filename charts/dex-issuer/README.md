# dex-issuer

![Version: 0.14.1](https://img.shields.io/badge/Version-0.14.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

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

## Adopting a pre-existing Postgres claim

`database.claimName`, `database.identifier`, and `database.connectionSecretName` default to
`"dex"`, `"<resourcePrefix>-dex"`, and `"dex-postgres-connection"` respectively. If this chart is
replacing an existing, non-chart-managed Dex deployment that already has its own `Postgres` claim
writing to a connection secret, set these three to match that claim's `metadata.name`,
`spec.parameters.identifier`, and `spec.writeConnectionSecretToRef.name` exactly. The claim this
chart renders then has the same identity as the existing one, so Crossplane reconciles it in place
instead of creating a second claim that collides on `connectionSecretName` (the second claim's
`writeConnectionSecretToRef` fails validation: a `Secret` can only have one owning controller) and
is left orphaned, half-provisioned, forever retrying. Leave all three unset for a fresh install.

## Barman backups and the object store

`database.barmanBackup.enabled` turns on continuous WAL archiving plus a daily base backup,
handled by the CNPG barman-cloud plugin. The claim's `barmanBackup` block is rendered with
`enabled` and `retentionDays` always, and the rest only when set.

**Credential mode.** `database.barmanBackup.credentialsSecretRef.name` selects it:

- **unset** — AWS IRSA. The postgres-cnpg composition renders an `iam.aws.m.upbound.io`
  Role/Policy/RolePolicyAttachment and an IRSA `serviceAccountTemplate` annotation. A cluster
  with no AWS provider cannot compose those at all, and the failure aborts the *whole*
  composition — no CNPG Cluster, no connection secret.
- **set** — static keys. The IAM resources and the IRSA annotation are not rendered, so the
  composition composes on a cluster with no AWS provider. This is also what a self-hosted
  S3-compatible store needs.

The Secret is referenced by name only. **This chart never creates it and never reads it** —
create it out of band, in the claim's namespace:

```bash
kubectl create secret generic cnpg-s3-creds \
  --namespace <ns> \
  --from-literal=ACCESS_KEY_ID=<access key> \
  --from-literal=ACCESS_SECRET_KEY=<secret key>
```

`accessKeyIdKey` and `secretAccessKeyKey` name the keys inside it, if they are not the
barman defaults `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY`.

**Endpoint.** `database.barmanBackup.endpointURL` points the archive at an S3-compatible
store (RustFS, MinIO, Garage, ...). Leave it empty for AWS S3. A plain-`http` endpoint needs
no CA bundle; a self-signed `https` one additionally needs the composition's `endpointCA`.

**Naming.** `bucketName` and `bucketPrefix` default, in the composition, to
`<resourcePrefix>-barman` and `<namespace>/<identifier>`. `serverName` is the barman server
name for ongoing WAL archiving and defaults to `<identifier>-wal`; it must differ from the
server name a restore reads from, or CNPG refuses to recover ("Expected empty archive").

**The plugin is a separate prerequisite.** The `objectstores.barmancloud.cnpg.io` CRD has to
exist before a claim with `barmanBackup.enabled: true` can be composed at all.

## Theme

`theme.enabled` (default `true`) mounts a ConfigMap with keys `styles.css`, `philips-logo.svg`,
`logo.png` into Dex. By default this chart creates that ConfigMap itself from the bundled
`files/theme/*`. Set `theme.existingConfigMap` to the name of your own ConfigMap (same three keys,
same namespace as Dex) to use custom branding instead — this chart then skips creating its own
ConfigMap and just points Dex's volume at yours, so no forking is needed. Manage that ConfigMap
however you like (a kustomize `configMapGenerator`, a separate chart, …); this chart does not
touch it.

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
| database.barmanBackup.bucketName | string | `""` |  |
| database.barmanBackup.bucketPrefix | string | `""` |  |
| database.barmanBackup.compression | string | `""` |  |
| database.barmanBackup.credentialsSecretRef.accessKeyIdKey | string | `"ACCESS_KEY_ID"` |  |
| database.barmanBackup.credentialsSecretRef.name | string | `""` |  |
| database.barmanBackup.credentialsSecretRef.secretAccessKeyKey | string | `"ACCESS_SECRET_KEY"` |  |
| database.barmanBackup.enabled | bool | `true` |  |
| database.barmanBackup.endpointURL | string | `""` |  |
| database.barmanBackup.maxParallel | int | `0` |  |
| database.barmanBackup.retentionDays | int | `7` |  |
| database.barmanBackup.scheduleBaseBackup | string | `""` |  |
| database.barmanBackup.serverName | string | `""` |  |
| database.claimName | string | `""` |  |
| database.cnpg | bool | `true` |  |
| database.connectionSecretName | string | `""` |  |
| database.enableSnapshots | bool | `true` |  |
| database.engineVersion | string | `""` |  |
| database.identifier | string | `""` |  |
| database.size | string | `"xsmall"` |  |
| database.snapshotClassName | string | `""` |  |
| database.storageClassName | string | `""` |  |
| dex.allowedScopePrefixes[0] | string | `"hsp:iam:introspect"` |  |
| dex.dcr.enabled | bool | `true` |  |
| dex.enterpriseManagedAuthorization.accountLinkingByEmail | bool | `false` |  |
| dex.enterpriseManagedAuthorization.enabled | bool | `false` |  |
| dex.enterpriseManagedAuthorization.trustedIssuers | list | `[]` |  |
| dex.expiry.idTokens | string | `"8h"` |  |
| dex.expiry.signingKeys | string | `"6h"` |  |
| dex.frontendIssuer | string | `"DIP Services"` |  |
| dex.grantTypes | list | `[]` |  |
| dex.httpRoute.enabled | bool | `true` |  |
| dex.httpRoute.host | string | `"issuer"` |  |
| dex.httpRoute.sharedGatewayName | string | `"platform"` |  |
| dex.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| dex.image.repository | string | `"ghcr.io/philips-forks/dex"` |  |
| dex.image.tag | string | `"v2.46.0-dip.3"` |  |
| dex.ingress.enabled | bool | `false` |  |
| dex.ingress.host | string | `"issuer"` |  |
| dex.ingress.ingressClassName | string | `"nginx"` |  |
| dex.issuerURL | string | `""` |  |
| dex.logLevel | string | `"info"` |  |
| dex.replicas | int | `2` |  |
| dex.resources.limits.memory | string | `"128Mi"` |  |
| dex.resources.requests.cpu | string | `"10m"` |  |
| dex.resources.requests.memory | string | `"128Mi"` |  |
| dex.serviceMonitor.enabled | bool | `true` |  |
| dex.sessions.absoluteLifetime | string | `"24h"` |  |
| dex.sessions.cookieEncryptionKey | string | `""` |  |
| dex.sessions.cookieName | string | `"dex_session"` |  |
| dex.sessions.enabled | bool | `false` |  |
| dex.sessions.rememberMeCheckedByDefault | bool | `true` |  |
| dex.sessions.ssoSharedWithDefault | string | `"none"` |  |
| dex.sessions.validIfNotUsedFor | string | `"1h"` |  |
| dex.staticClients | list | `[]` |  |
| dex.staticClientsSecret.enabled | bool | `false` |  |
| dex.staticClientsSecret.name | string | `"dex-static-clients"` |  |
| dex.tokenExchange.tokenTypes | list | `[]` |  |
| dexChart.releaseName | string | `"dex"` |  |
| dexChart.repoURL | string | `"https://charts.dexidp.io"` |  |
| dexChart.version | string | `"0.26.0"` |  |
| environmentConfig.clusterFqdn | string | `""` |  |
| environmentConfig.customFqdn | string | `""` |  |
| environmentConfig.managedBy | string | `""` |  |
| environmentConfig.owner | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| pki.caDuration | string | `"87600h"` |  |
| pki.caNamespace | string | `"cert-manager"` |  |
| pki.caRenewBefore | string | `"8760h"` |  |
| pki.certDuration | string | `"8760h"` |  |
| pki.certRenewBefore | string | `"720h"` |  |
| pki.clientNamespace | string | `"crossplane-system"` |  |
| pki.existingClusterIssuer | string | `""` |  |
| pki.grpcMtlsEnabled | bool | `false` |  |
| provider.cascadeDelete | bool | `false` |  |
| provider.crossplaneProvidersVersion | string | `"0.0.40"` |  |
| provider.debug | bool | `true` |  |
| provider.enabled | bool | `true` |  |
| provider.providerConfigNamespaces | list | `[]` |  |
| provider.registry | string | `"ghcr.io/loafoe"` |  |
| provider.tag | string | `"v1.15.0"` |  |
| theme.enabled | bool | `true` |  |
| theme.existingConfigMap | string | `""` |  |
| useCustomFqdn | bool | `false` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
