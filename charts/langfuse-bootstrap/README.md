# langfuse-bootstrap

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 4.17.0](https://img.shields.io/badge/AppVersion-4.17.0-informational?style=flat-square)

Deploys [Langfuse](https://langfuse.com/) via ArgoCD: CNPG Postgres, ClickHouse (rendered by the upstream chart against a pre-installed [ClickHouse Operator](../clickhouse-operator-bootstrap)), a self-managed single-instance Valkey, and S3 access via IRSA against an existing bucket.

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

Set `ingress.httpRoute.enabled: true` (required for a real OAuth callback URL) and `sso.enabled: true` to sign in via the same Dex IdP centcom uses (`https://issuer.ri-obs-use1.hsp.philips.com`, running on the `ri-obs-use1-prd` cluster). Prerequisite: register a Dex `Client` CR there first - see `philips-internal/dip-oaas-ri-observability`'s `kustomize/bootstrap/dex/base/clients/dip-ce-k3s-eu-langfuse.yaml` for the pattern - then copy the resulting `<name>-dex-creds` secret's `clientId`/`clientSecret` into `sso.clientId` / `credentials.ssoClientSecret`.

Langfuse OSS has no native groups-claim-to-role mapping, so new SSO users land with no organization membership. An existing org owner manually invites/promotes specific users (e.g. `philips-internal:homelab` members) to `ADMIN` via the Langfuse UI after their first sign-in.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argoProject | string | `"default"` |  |
| clickhouse.cluster.image.repository | string | `"clickhouse/clickhouse-server"` |  |
| clickhouse.cluster.image.tag | string | `"26.4"` |  |
| clickhouse.cluster.replicas | int | `1` |  |
| clickhouse.cluster.resources.limits.memory | string | `"2Gi"` |  |
| clickhouse.cluster.resources.requests.cpu | string | `"500m"` |  |
| clickhouse.cluster.resources.requests.memory | string | `"1Gi"` |  |
| clickhouse.cluster.storage.className | string | `""` |  |
| clickhouse.cluster.storage.size | string | `"20Gi"` |  |
| clickhouse.keeper.image.repository | string | `"clickhouse/clickhouse-keeper"` |  |
| clickhouse.keeper.image.tag | string | `"26.4"` |  |
| clickhouse.keeper.replicas | int | `1` |  |
| clickhouse.keeper.resources.limits.memory | string | `"512Mi"` |  |
| clickhouse.keeper.resources.requests.cpu | string | `"100m"` |  |
| clickhouse.keeper.resources.requests.memory | string | `"256Mi"` |  |
| clickhouse.keeper.storage.className | string | `""` |  |
| clickhouse.keeper.storage.size | string | `"5Gi"` |  |
| credentials.clickhousePassword | string | `"changeme-clickhouse-password-please-override"` |  |
| credentials.encryptionKey | string | `"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"` |  |
| credentials.nextauthSecret | string | `"changeme-nextauth-secret-please-override"` |  |
| credentials.postgresPassword | string | `"changeme-postgres-password-please-override"` |  |
| credentials.redisPassword | string | `"changeme-redis-password-please-override"` |  |
| credentials.salt | string | `"changeme-langfuse-salt-please-override"` |  |
| credentials.ssoClientSecret | string | `"changeme-sso-client-secret-please-override"` |  |
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
| ingress.httpRoute.sharedGatewayName | string | `"platform"` |  |
| ingress.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| langfuse.nextauthUrl | string | `"http://localhost:3000"` |  |
| langfuse.web.resources.limits.memory | string | `"2Gi"` |  |
| langfuse.web.resources.requests.cpu | string | `"100m"` |  |
| langfuse.web.resources.requests.memory | string | `"1Gi"` |  |
| langfuse.worker.resources.limits.memory | string | `"2Gi"` |  |
| langfuse.worker.resources.requests.cpu | string | `"100m"` |  |
| langfuse.worker.resources.requests.memory | string | `"1Gi"` |  |
| langfuseChart.repoURL | string | `"oci://ghcr.io/langfuse/langfuse-k8s/charts"` |  |
| langfuseChart.version | string | `"2.0.2"` |  |
| namespace | string | `"langfuse-system"` |  |
| redis.image.repository | string | `"valkey/valkey"` |  |
| redis.image.tag | string | `"8.0"` |  |
| redis.resources.limits.memory | string | `"512Mi"` |  |
| redis.resources.requests.cpu | string | `"50m"` |  |
| redis.resources.requests.memory | string | `"128Mi"` |  |
| redis.storage.size | string | `"4Gi"` |  |
| redis.storage.storageClass | string | `""` |  |
| sso.clientId | string | `""` |  |
| sso.disableUsernamePassword | bool | `false` |  |
| sso.enabled | bool | `false` |  |
| sso.issuer | string | `"https://issuer.ri-obs-use1.hsp.philips.com"` |  |
| sso.name | string | `"Philips SSO"` |  |
| sso.scope | string | `"openid email profile groups"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
