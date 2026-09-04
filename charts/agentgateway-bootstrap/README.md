# agentgateway-bootstrap

![Version: 0.7.28](https://img.shields.io/badge/Version-0.7.28-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.5.0](https://img.shields.io/badge/AppVersion-1.5.0-informational?style=flat-square)

A Helm chart for bootstrapping agentgateway with Amazon Bedrock support on Kubernetes via ArgoCD Applications.

## Deployment Modes

This chart supports two deployment modes via the `mode` value:

- **`kubernetes`** (default): Deploys upstream `agentgateway-crds` and `agentgateway` (controller) charts via ArgoCD Applications.
- **`standalone`**: Deploys upstream `agentgateway-standalone` chart via ArgoCD Application.

## Database Backup & Restore

The request-logging database (`database.*`) is a plain CNPG `Cluster` - no Crossplane, no Barman/S3 dependency, by design. Backups use CNPG's native **CSI VolumeSnapshot** support instead: a snapshot of the PGDATA PVC taken through the cluster's storage driver (e.g. `ebs.csi.aws.com` on EKS).

### Enabling backups

Backups are off by default because the `VolumeSnapshotClass` name is cluster-specific. Enable them via:

```yaml
database:
  backup:
    volumeSnapshot:
      enabled: true
      # Must match a VolumeSnapshotClass whose driver supports the cluster's StorageClass.
      className: ebs-csi-aws
      # Hot (online) backup via pg_backup_start/stop; false pauses WAL first for a cold snapshot.
      online: true
      # Optional cron schedule for automatic backups (creates a ScheduledBackup).
      # Leave empty to only take backups on demand.
      schedule: "0 0 3 * * *"
```

This adds `spec.backup.volumeSnapshot` to the `Cluster` and, if `schedule` is set, a `ScheduledBackup` (`method: volumeSnapshot`) targeting it.

### Taking an on-demand backup

Even with `schedule` unset, you can trigger a backup at any time by creating a `Backup` resource:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: agentgateway-gw-db-manual-1
  namespace: agentgateway-system
spec:
  cluster:
    name: agentgateway-gw-db
  method: volumeSnapshot
```

Check progress with `kubectl get backup -n agentgateway-system agentgateway-gw-db-manual-1` until `.status.phase` is `completed`. This produces a `VolumeSnapshot` (same namespace as the cluster) named after the backup.

### Restoring

CNPG restores a volume snapshot backup by **bootstrapping a new `Cluster`** from it - there is no in-place restore of an existing cluster. Point `bootstrap.recovery.volumeSnapshots.storage` at the `VolumeSnapshot` created by the backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: agentgateway-gw-db-restored
  namespace: agentgateway-system     # VolumeSnapshot is namespace-scoped - must match
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie  # match the source cluster's image
  bootstrap:
    recovery:
      volumeSnapshots:
        storage:
          name: agentgateway-gw-db-manual-1   # the VolumeSnapshot from the backup
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  storage:
    size: 5Gi
```

Wait for `kubectl get cluster -n agentgateway-system agentgateway-gw-db-restored` to report `status.readyInstances: 1`, then verify the data (e.g. `kubectl exec ... -c postgres -- psql -U postgres -d agentgateway -c 'SELECT count(*) FROM request_logs;'`).

To actually recover production data with this, either point `database.clusterName` / the app's connection secret at the restored cluster, or `pg_dump` from it and `pg_restore` into the original cluster - then delete the temporary restored `Cluster` and its PVC once you're done.

**Notes:**
- The recovery `Cluster` needs `imageName` set explicitly (matching the source cluster) unless the target environment has a `ClusterImageCatalog` named `default` - not all clusters do.
- This flow was live-tested end-to-end (backup → restore → verified identical row counts/checksums → cleanup) against a real deployment; see the chart's git history for details.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agentgatewayChart.repoURL | string | `"oci://cr.agentgateway.dev/charts"` |  |
| agentgatewayChart.version | string | `"1.5.0"` |  |
| agentgatewayCrdsChart.repoURL | string | `"oci://cr.agentgateway.dev/charts"` |  |
| agentgatewayCrdsChart.version | string | `"1.5.0"` |  |
| agentgatewayStandaloneChart.repoURL | string | `"oci://cr.agentgateway.dev/charts"` |  |
| agentgatewayStandaloneChart.version | string | `"1.5.0"` |  |
| argoProject | string | `"default"` |  |
| bedrock.auth.roleArn | string | `""` |  |
| bedrock.auth.secretName | string | `"bedrock-secret"` |  |
| bedrock.auth.type | string | `"irsa"` |  |
| bedrock.enabled | bool | `true` |  |
| bedrock.model | string | `"amazon.nova-micro-v1:0"` |  |
| bedrock.region | string | `"us-east-1"` |  |
| bedrock.route.enabled | bool | `true` |  |
| bedrock.route.openAiPath | string | `"/v1/chat/completions"` |  |
| bedrock.route.path | string | `"/bedrock"` |  |
| controller.logLevel | string | `"info"` |  |
| controller.replicaCount | int | `1` |  |
| controller.resources.limits.memory | string | `"256Mi"` |  |
| controller.resources.requests.cpu | string | `"100m"` |  |
| controller.resources.requests.memory | string | `"128Mi"` |  |
| database.backup.volumeSnapshot.className | string | `""` |  |
| database.backup.volumeSnapshot.enabled | bool | `false` |  |
| database.backup.volumeSnapshot.online | bool | `true` |  |
| database.backup.volumeSnapshot.schedule | string | `""` |  |
| database.clusterName | string | `""` |  |
| database.databaseName | string | `"agentgateway"` |  |
| database.enabled | bool | `true` |  |
| database.instances | int | `2` |  |
| database.password | string | `"agentgateway123"` |  |
| database.resources.limits.memory | string | `"512Mi"` |  |
| database.resources.requests.cpu | string | `"50m"` |  |
| database.resources.requests.memory | string | `"128Mi"` |  |
| database.storage.size | string | `"5Gi"` |  |
| database.storage.storageClass | string | `""` |  |
| environmentConfig.accountId | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| gateway.className | string | `"agentgateway"` |  |
| gateway.enabled | bool | `true` |  |
| gateway.name | string | `"agentgateway-gw"` |  |
| gateway.namespace | string | `"agentgateway-system"` |  |
| gateway.service.type | string | `"ClusterIP"` |  |
| jwt.audiences | list | `[]` |  |
| jwt.cacheDuration | string | `"5m"` |  |
| jwt.enabled | bool | `false` |  |
| jwt.externalIssuer.host | string | `""` |  |
| jwt.externalIssuer.jwksPath | string | `"/keys"` |  |
| jwt.externalIssuer.port | int | `443` |  |
| jwt.externalIssuer.sni | string | `""` |  |
| jwt.issuer | string | `""` |  |
| mode | string | `"kubernetes"` |  |
| monitoring.enabled | bool | `true` |  |
| monitoring.grafanaDashboard.enabled | bool | `true` |  |
| monitoring.serviceMonitor.enabled | bool | `true` |  |
| monitoring.serviceMonitor.interval | string | `"15s"` |  |
| openrouter.enabled | bool | `true` |  |
| proxy.logLevel | string | `"info"` |  |
| standalone.image.registry | string | `""` |  |
| standalone.image.repository | string | `""` |  |
| standalone.image.tag | string | `""` |  |
| standalone.replicaCount | int | `1` |  |
| standalone.service.type | string | `"ClusterIP"` |  |
| standaloneTracing.authHeaderSecret.key | string | `"OTLP_AUTH_HEADER"` |  |
| standaloneTracing.authHeaderSecret.name | string | `""` |  |
| standaloneTracing.enabled | bool | `false` |  |
| standaloneTracing.headers | object | `{}` |  |
| standaloneTracing.otlpEndpoint | string | `""` |  |
| standaloneTracing.otlpProtocol | string | `"http"` |  |
| standaloneTracing.path | string | `"/v1/traces"` |  |
| standaloneTracing.randomSampling | bool | `true` |  |
| tracing.attributes.add[0].expression | string | `"request.host"` |  |
| tracing.attributes.add[0].name | string | `"host"` |  |
| tracing.backendRef.name | string | `"otlp-gateway"` |  |
| tracing.backendRef.namespace | string | `"otlp-gateway"` |  |
| tracing.backendRef.port | int | `4317` |  |
| tracing.clientSampling | string | `"true"` |  |
| tracing.enabled | bool | `false` |  |
| tracing.protocol | string | `"GRPC"` |  |
| tracing.randomSampling | string | `"1.0"` |  |
| tracing.resources[0].expression | string | `"\"production\""` |  |
| tracing.resources[0].name | string | `"deployment.environment.name"` |  |
| ui.authorization.groups | list | `[]` |  |
| ui.enabled | bool | `true` |  |
| ui.oidc.clientId | string | `""` |  |
| ui.oidc.enabled | bool | `false` |  |
| ui.oidc.issuer | string | `""` |  |
| ui.oidc.redirectURI | string | `""` |  |
| ui.oidc.scopes | list | `[]` |  |
| ui.service.port | int | `15000` |  |
| ui.service.targetPort | int | `15000` |  |
| ui.service.type | string | `"ClusterIP"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)

