# mimir

![Version: 0.69.1](https://img.shields.io/badge/Version-0.69.1-informational?style=flat-square)

# Deployment

## Using helm

```shell
helm upgrade --install oci://ghcr.io/philips-software/helm-charts/mimir-bootstrap:0.69.1 -n monitoring
```

## Dependencies

The application uses [Crossplane](https://www.crossplane.io) to manage the required IAM roles

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| adminCache.replicas | int | `2` | Number of admin-cache replicas |
| argoProject | string | `"default"` |  |
| chunksCache.replicas | int | `2` | Number of chunks-cache replicas |
| compactor.persistentVolume.size | string | `"80Gi"` | Size of the persistent volume for compactor |
| compactor.resources.limits.memory | string | `"512Mi"` |  |
| compactor.resources.requests.cpu | string | `"100m"` |  |
| compactor.resources.requests.memory | string | `"256Mi"` |  |
| compactorOrgmapper.package | string | `"ghcr.io/loafoe/compactor-orgmapper"` |  |
| compactorOrgmapper.tag | string | `"v0.0.1"` |  |
| distributor.replicas | int | `6` | Number of distributor replicas |
| environmentConfig.managedBy | string | `""` |  |
| environmentConfig.owner | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| existingBucketName | string | `""` |  |
| gateway.replicas | int | `3` | Number of gateway replicas |
| indexCache.replicas | int | `2` | Number of index-cache replicas |
| ingester.persistentVolume.size | string | `"100Gi"` | Size of the persistent volume for each ingester replica |
| ingester.replicas | int | `9` | Number of ingester replicas |
| ingester.replicationFactor | int | `3` | Replication factor for ingested data. RF=3 (default): Data replicated to 3 zones, can survive 2 zone failures. RF=2: Data replicated to 2 zones, saves ~33% ingester memory but less durable. |
| ingester.resources.limits.memory | string | `"8Gi"` |  |
| ingester.resources.requests.cpu | string | `"200m"` |  |
| ingester.resources.requests.memory | string | `"4Gi"` |  |
| initOverrides.package | string | `"busybox"` |  |
| initOverrides.tag | string | `"1.38.0"` |  |
| kafka.persistence.size | string | `"100Gi"` |  |
| kafkaNodePool.consolidationPolicy | string | `"WhenEmpty"` |  |
| kafkaNodePool.enabled | bool | `true` |  |
| kafkaNodePool.expireAfter | string | `"3600h"` |  |
| kafkaNodePool.labels.workload | string | `"kafka"` |  |
| kafkaNodePool.minInstanceMemoryMiB | int | `8000` |  |
| kafkaNodePool.name | string | `"kafka-nodepool"` | Karpenter NodePool name. Prefer "mimir-kafka-nodepool"; the default is the legacy cluster-generic name. Changing this REPLACES the nodes (Argo CD prunes the old NodePool, Karpenter drains it), briefly taking the sole Kafka broker offline -- treat it as a maintenance window and read the notes in values.yaml first. |
| kafkaNodePool.nodeClassRefName | string | `"bottlerocket-v2"` |  |
| kafkaNodePool.resources.limits.cpu | int | `4` |  |
| kafkaNodePool.resources.limits.memory | string | `"16Gi"` |  |
| kafkaNodePool.taintKey | string | `"cilium.hsp.philips.com/dedicated"` |  |
| karpenter.doNotDisrupt | bool | `false` |  |
| limits.maxGlobalExemplarsPerUser | int | `0` |  |
| limits.maxLabelNamesPerSeries | int | `35` |  |
| limits.outOfOrderTimeWindow | string | `"30m"` |  |
| mimirChart.version | string | `"6.2.1"` |  |
| mimirProvider.alertmanagerUri | string | `"http://mimir-gateway.mimir-system.svc.cluster.local"` |  |
| mimirProvider.credentials.authType | string | `"basic"` |  |
| mimirProvider.credentials.passwordKey | string | `"password"` |  |
| mimirProvider.credentials.secretName | string | `"mimir-provider-credentials"` |  |
| mimirProvider.credentials.tokenKey | string | `"token"` |  |
| mimirProvider.credentials.usernameKey | string | `"username"` |  |
| mimirProvider.enabled | bool | `false` |  |
| mimirProvider.orgId | string | `"anonymous"` |  |
| mimirProvider.package | string | `"ghcr.io/loafoe/provider-mimir"` |  |
| mimirProvider.rulerUri | string | `"http://mimir-gateway.mimir-system.svc.cluster.local/prometheus"` |  |
| mimirProvider.tag | string | `"v1.3.1"` |  |
| mimirProvider.uri | string | `"http://mimir-gateway.mimir-system.svc.cluster.local/prometheus"` |  |
| multitenancyEnabled | bool | `true` |  |
| priorityClass | object | `{"enabled":true,"name":"mimir-stateful","value":1000000}` | PriorityClass for the stateful write path (ingesters and the ingest-storage kafka): these hold not-yet-flushed data, so if they are evicted or left Pending on a full node, ingestion stalls and un-replicated data is at risk. Without it they run at the default priority 0, the same as every stateless query/read pod, and can be preempted by (or fail to preempt) any of them. The value sits well below the built-in system-node-critical/system-cluster-critical classes, so node agents and cluster add-ons still win. Created by this chart with a chart-specific name, so it does not clash with the loki/mimir/tempo-bootstrap siblings. Note: a PriorityClass value is immutable; to change it, also change the name. |
| querier.resources.limits.memory | string | `"1.5Gi"` |  |
| querier.resources.requests.cpu | string | `"100m"` |  |
| querier.resources.requests.memory | string | `"512Mi"` |  |
| queryEngine.enableRemoteExecution | bool | `false` | [experimental] MQE remote execution requires every querier to report a compatible "query plan version" via the ring; this negotiation is flaky under churn (observed as intermittent 500s: "could not determine maximum supported query plan version ... at least one querier in the ring is not reporting a supported query plan version", even while the flagged querier was actively evaluating other queries successfully at the same time). Keep disabled until upstream stabilizes this.  Also gates use-mimir-query-engine-for-sharding, which defaults to true and requires remote execution to be enabled -- mismatched settings fail startup config validation, so both flags are driven by this one value. |
| queryFrontend.replicas | int | `3` | Number of query-frontend replicas |
| queryFrontend.resources.limits.memory | string | `"3Gi"` |  |
| queryFrontend.resources.requests.cpu | string | `"100m"` |  |
| queryFrontend.resources.requests.memory | string | `"512Mi"` |  |
| resultsCache.replicas | int | `4` | Number of results-cache replicas |
| ruler.maxRulesPerRuleGroup | int | `1200` |  |
| ruler.resources.limits.memory | string | `"2Gi"` |  |
| ruler.resources.requests.cpu | string | `"100m"` |  |
| ruler.resources.requests.memory | string | `"1Gi"` |  |
| runtimeConfig.distributor_limits.max_inflight_push_requests | int | `60000` |  |
| runtimeConfig.distributor_limits.max_inflight_push_requests_bytes | int | `50000000` |  |
| runtimeConfig.distributor_limits.max_ingestion_rate | int | `80000` |  |
| runtimeConfig.ingester_limits.max_ingestion_rate | int | `80000` |  |
| store_gateway.persistentVolume.size | string | `"10Gi"` | Size of the persistent volume for each store-gateway replica |
| store_gateway.resources.limits.memory | string | `"3Gi"` |  |
| store_gateway.resources.requests.cpu | string | `"100m"` |  |
| store_gateway.resources.requests.memory | string | `"512Mi"` |  |
| vpa.components.distributor.enabled | bool | `true` |  |
| vpa.components.distributor.maxAllowed.cpu | int | `1` |  |
| vpa.components.distributor.maxAllowed.memory | string | `"8Gi"` |  |
| vpa.components.distributor.minAllowed.cpu | string | `"350m"` |  |
| vpa.components.distributor.minAllowed.memory | string | `"512Mi"` |  |
| vpa.components.ingester.enabled | bool | `true` |  |
| vpa.components.ingester.maxAllowed.cpu | int | `1` |  |
| vpa.components.ingester.maxAllowed.memory | string | `"16Gi"` |  |
| vpa.components.ingester.minAllowed.cpu | string | `"350m"` |  |
| vpa.components.ingester.minAllowed.memory | string | `"2Gi"` |  |
| vpa.components.querier.enabled | bool | `true` |  |
| vpa.components.querier.maxAllowed.cpu | string | `"500m"` |  |
| vpa.components.querier.maxAllowed.memory | string | `"2Gi"` |  |
| vpa.components.querier.minAllowed.cpu | string | `"100m"` |  |
| vpa.components.querier.minAllowed.memory | string | `"128Mi"` |  |
| vpa.components.queryFrontend.enabled | bool | `true` |  |
| vpa.components.queryFrontend.maxAllowed.cpu | string | `"500m"` |  |
| vpa.components.queryFrontend.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.queryFrontend.minAllowed.cpu | string | `"100m"` |  |
| vpa.components.queryFrontend.minAllowed.memory | string | `"128Mi"` |  |
| vpa.enabled | bool | `true` | Enable VPA resources for Mimir components |
| vpa.updateMode | string | `"Auto"` | VPA update mode (e.g. Off, Initial, Auto, InPlaceOrRecreate) |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
