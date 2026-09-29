# langfuse-bootstrap

![Version: 0.7.0](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Deploys [Langfuse](https://langfuse.com/) via ArgoCD: CNPG Postgres, ClickHouse (rendered by the upstream chart against a pre-installed [ClickHouse Operator](../clickhouse-operator-bootstrap)), a self-managed single-instance Valkey, and S3 access (IRSA or static credentials) against an existing bucket.

## Credentials

This chart stores **no secret material in its values**. Credentials are split in two:

1. **Generated in-cluster** by the pre-install/pre-upgrade Job `langfuse-credentials-init`
   (also an ArgoCD `PreSync` hook): `salt`, `encryption-key`, `nextauth-secret`,
   `clickhouse-password`, `redis-password` in the `langfuse-credentials` Secret.
   A value is generated **only when its key is absent**; existing values are preserved
   byte-for-byte. Re-syncing therefore never rotates `salt`/`encryption-key` (which would
   invalidate hashed API keys and encrypted data).

   The CNPG application-user password is **not** handled by that Job and **not** in values.
   This chart sets no `bootstrap.initdb.secret`: CNPG generates and owns the password and
   publishes it in the `<database.clusterName|langfuse-db>-app` Secret (keys incl. `username`,
   `password`, `uri`), which the upstream chart reads via `postgresql.auth.existingSecret`.
   This keeps the role password and the Secret consumers read in lockstep. (Setting an
   explicit `bootstrap.initdb.secret` is a known footgun: CNPG uses it for the role but still
   generates `<cluster>-app` with a *different* password, and the two then diverge.)
   Rotate via CNPG's own mechanism - e.g. delete the `<cluster>-app` Secret so the operator
   regenerates it and reconciles the role - and do not hand-edit that Secret.

   > **Upgrading from a chart that did set `bootstrap.initdb.secret`:** CNPG reads
   > `bootstrap.initdb` only during `initdb`. Removing the field from an already-bootstrapped
   > cluster makes the operator create `<cluster>-app` with a **fresh** password and
   > immediately reconcile the role to it, so the old password stops working at once. Repoint
   > every consumer to `<cluster>-app` in the **same** change, and delete the now-stale
   > `<cluster>-credentials` Secret. Verified against CNPG 1.28.1.

2. **Provided out-of-band** in pre-existing Secrets this chart only references:
   - `sso.existingSecret` (key `sso.existingSecretKey`, default `clientSecret`) — OAuth2
     client secret. Required when `sso.enabled` is true.
   - `s3.secretConfig.existingSecret` (keys `accessKeyId`/`secretAccessKey`) — static S3
     keys. Required when `s3.authType` is `secret`.

   Create those before the first sync (same model as `grafana`'s `grafana-sso-creds`).

> The target `namespace` must already exist before install, since the init Job and its
> RBAC are created there.

## Prerequisites

- `clickhouse-operator-bootstrap` installed cluster-wide (provides the `ClickHouseCluster`/`KeeperCluster` CRDs this chart's upstream dependency renders against).
- CloudNativePG operator installed cluster-wide (see `cloudnative-pg-operator`).
- An existing S3 bucket (set via `existingBucketName`) and IRSA support in-cluster (see `loki-bootstrap` for the same pattern).

## Reaching the login screen

By default this chart exposes Langfuse as ClusterIP only:

```bash
kubectl port-forward svc/langfuse-web 3000:3000 -n langfuse-system
```

Then browse to http://localhost:3000.

## SSO (optional)

Set `ingress.httpRoute.enabled: true` (required for a real OAuth callback URL) and `sso.enabled: true` to sign in via an external Dex/OIDC IdP. Prerequisite: register an OAuth2 client with that IdP first (see this repo's `dex-issuer` chart for the Crossplane `provider-dex` pattern), then set `sso.issuer` / `sso.clientId` and create the out-of-band Secret referenced by `sso.existingSecret`:

```bash
kubectl -n langfuse-system create secret generic langfuse-sso-creds \
  --from-literal=clientSecret=<client-secret-from-dex>
```

## S3 static credentials (optional)

When `s3.authType: secret` (Garage/MinIO/SeaweedFS), create the out-of-band Secret referenced by `s3.secretConfig.existingSecret`:

```bash
kubectl -n langfuse-system create secret generic langfuse-s3-creds \
  --from-literal=accessKeyId=<key-id> \
  --from-literal=secretAccessKey=<secret>
```

Langfuse OSS has no native groups-claim-to-role mapping, so new SSO users land with no organization membership. An existing org owner manually invites/promotes specific users (e.g. `philips-internal:homelab` members) to `ADMIN` via the Langfuse UI after their first sign-in.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argoProject | string | `"default"` |  |
| clickhouse.cluster.affinity | object | `{}` |  |
| clickhouse.cluster.image.repository | string | `"clickhouse/clickhouse-server"` |  |
| clickhouse.cluster.image.tag | string | `"26.9"` |  |
| clickhouse.cluster.nodeSelector | object | `{}` |  |
| clickhouse.cluster.replicas | int | `1` |  |
| clickhouse.cluster.resources.limits.memory | string | `"2Gi"` |  |
| clickhouse.cluster.resources.requests.cpu | string | `"500m"` |  |
| clickhouse.cluster.resources.requests.memory | string | `"1Gi"` |  |
| clickhouse.cluster.storage.className | string | `""` |  |
| clickhouse.cluster.storage.size | string | `"20Gi"` |  |
| clickhouse.cluster.tolerations | list | `[]` |  |
| clickhouse.keeper.affinity | object | `{}` |  |
| clickhouse.keeper.image.repository | string | `"clickhouse/clickhouse-keeper"` |  |
| clickhouse.keeper.image.tag | string | `"26.9"` |  |
| clickhouse.keeper.nodeSelector | object | `{}` |  |
| clickhouse.keeper.replicas | int | `1` |  |
| clickhouse.keeper.resources.limits.memory | string | `"512Mi"` |  |
| clickhouse.keeper.resources.requests.cpu | string | `"100m"` |  |
| clickhouse.keeper.resources.requests.memory | string | `"256Mi"` |  |
| clickhouse.keeper.storage.className | string | `""` |  |
| clickhouse.keeper.storage.size | string | `"5Gi"` |  |
| clickhouse.keeper.tolerations | list | `[]` |  |
| database.clusterName | string | `""` |  |
| database.databaseName | string | `"langfuse"` |  |
| database.instances | int | `1` |  |
| database.resources.limits.memory | string | `"512Mi"` |  |
| database.resources.requests.cpu | string | `"50m"` |  |
| database.resources.requests.memory | string | `"128Mi"` |  |
| database.storage.size | string | `"5Gi"` |  |
| database.storage.storageClass | string | `""` |  |
| environmentConfig.accountId | string | `""` |  |
| environmentConfig.clusterFqdn | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| existingBucketName | string | `""` |  |
| ingress.httpRoute.enabled | bool | `false` |  |
| ingress.httpRoute.host | string | `"langfuse"` |  |
| ingress.httpRoute.sectionName | string | `""` |  |
| ingress.httpRoute.sharedGatewayName | string | `"platform"` |  |
| ingress.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| langfuse.image.tag | string | `"4.46.0"` |  |
| langfuse.nextauthUrl | string | `"http://localhost:3000"` |  |
| langfuse.revisionHistoryLimit | int | `3` |  |
| langfuse.web.livenessProbe.failureThreshold | int | `6` |  |
| langfuse.web.livenessProbe.initialDelaySeconds | int | `45` |  |
| langfuse.web.livenessProbe.timeoutSeconds | int | `10` |  |
| langfuse.web.readinessProbe.failureThreshold | int | `6` |  |
| langfuse.web.readinessProbe.initialDelaySeconds | int | `45` |  |
| langfuse.web.readinessProbe.timeoutSeconds | int | `10` |  |
| langfuse.web.resources.limits.memory | string | `"2Gi"` |  |
| langfuse.web.resources.requests.cpu | string | `"100m"` |  |
| langfuse.web.resources.requests.memory | string | `"1Gi"` |  |
| langfuse.worker.livenessProbe.failureThreshold | int | `8` |  |
| langfuse.worker.livenessProbe.initialDelaySeconds | int | `60` |  |
| langfuse.worker.livenessProbe.timeoutSeconds | int | `10` |  |
| langfuse.worker.resources.limits.memory | string | `"2Gi"` |  |
| langfuse.worker.resources.requests.cpu | string | `"100m"` |  |
| langfuse.worker.resources.requests.memory | string | `"1Gi"` |  |
| langfuseChart.repoURL | string | `"oci://ghcr.io/langfuse/langfuse-k8s/charts"` |  |
| langfuseChart.version | string | `"2.1.3"` |  |
| namespace | string | `"langfuse-system"` |  |
| redis.image.repository | string | `"valkey/valkey"` |  |
| redis.image.tag | string | `"9.2"` |  |
| redis.resources.limits.memory | string | `"512Mi"` |  |
| redis.resources.requests.cpu | string | `"50m"` |  |
| redis.resources.requests.memory | string | `"128Mi"` |  |
| redis.storage.size | string | `"4Gi"` |  |
| redis.storage.storageClass | string | `""` |  |
| s3.authType | string | `"irsa"` |  |
| s3.secretConfig.accessKeyIdKey | string | `"accessKeyId"` |  |
| s3.secretConfig.endpoint | string | `""` |  |
| s3.secretConfig.existingSecret | string | `""` |  |
| s3.secretConfig.forcePathStyle | bool | `true` |  |
| s3.secretConfig.region | string | `"garage"` |  |
| s3.secretConfig.secretAccessKeyKey | string | `"secretAccessKey"` |  |
| sso.allowAccountLinking | bool | `false` |  |
| sso.clientId | string | `""` |  |
| sso.disableUsernamePassword | bool | `false` |  |
| sso.enabled | bool | `false` |  |
| sso.existingSecret | string | `""` |  |
| sso.existingSecretKey | string | `"clientSecret"` |  |
| sso.issuer | string | `""` |  |
| sso.name | string | `"SSO"` |  |
| sso.scope | string | `"openid email profile groups"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
