# tempo

![Version: 0.45.4](https://img.shields.io/badge/Version-0.45.4-informational?style=flat-square)

# Deployment

## Using helm

```shell
helm upgrade --install oci://ghcr.io/philips-software/helm-charts/tempo-bootstrap:0.45.4 -n monitoring
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argoProject | string | `"default"` |  |
| blockBuilder.replicas | int | `3` | Number of block-builder replicas |
| compactor.replicas | int | `1` | Number of compactor replicas |
| compactorOrgmapper.package | string | `"ghcr.io/loafoe/compactor-orgmapper"` |  |
| compactorOrgmapper.tag | string | `"v0.0.1"` |  |
| distributor.replicas | int | `2` | Number of distributor replicas |
| environmentConfig.accountId | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| existingBucketName | string | `""` |  |
| gateway.replicas | int | `2` | Number of gateway replicas |
| initOverrides.package | string | `"busybox"` |  |
| initOverrides.tag | string | `"1.38.0"` |  |
| kafka.partitions | int | `3` | Partitions of the tempo-traces topic. Each live-store and each block-builder owns exactly one partition, so this must equal liveStore.replicas and blockBuilder.replicas (enforced at render time). Only applies when the broker auto-creates the topic: raising it later needs a manual partition increase on the existing topic. |
| kafka.persistence.size | string | `"100Gi"` |  |
| kafkaNodePool.consolidationPolicy | string | `"WhenEmpty"` |  |
| kafkaNodePool.enabled | bool | `true` |  |
| kafkaNodePool.expireAfter | string | `"3600h"` |  |
| kafkaNodePool.labels.workload | string | `"tempo-kafka"` |  |
| kafkaNodePool.name | string | `"tempo-kafka-nodepool"` | Karpenter NodePool name. Changing this REPLACES the nodes (Argo CD prunes the old NodePool, Karpenter drains it), briefly taking the sole Kafka broker offline -- treat it as a maintenance window. |
| kafkaNodePool.nodeClassRefName | string | `"bottlerocket-v2"` |  |
| kafkaNodePool.resources.limits.cpu | int | `4` |  |
| kafkaNodePool.resources.limits.memory | string | `"16Gi"` |  |
| kafkaNodePool.taintKey | string | `"cilium.hsp.philips.com/dedicated"` |  |
| liveStore.replicas | int | `3` | Number of live-store replicas |
| multitenancyEnabled | bool | `true` |  |
| priorityClass | object | `{"enabled":true,"name":"tempo-stateful","value":1000000}` | PriorityClass for the stateful write path (live-store and tempo-kafka): these hold not-yet-flushed data, so if they are evicted or left Pending on a full node, ingestion stalls and un-replicated data is at risk. Without it they run at the default priority 0, the same as every stateless query/read pod, and can be preempted by (or fail to preempt) any of them. The value sits well below the built-in system-node-critical/system-cluster-critical classes, so node agents and cluster add-ons still win. Created by this chart with a chart-specific name, so it does not clash with the loki/mimir/tempo-bootstrap siblings. Note: a PriorityClass value is immutable; to change it, also change the name. |
| querier.replicas | int | `2` | Number of querier replicas |
| queryFrontend.replicas | int | `2` | Number of query-frontend replicas |
| streamOverHTTPEnabled | bool | `true` |  |
| tempoChart.version | string | `"3.14.0"` |  |
| vpa.components.backendScheduler.enabled | bool | `true` |  |
| vpa.components.backendScheduler.maxAllowed.cpu | int | `1` |  |
| vpa.components.backendScheduler.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.backendScheduler.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.backendScheduler.minAllowed.memory | string | `"100Mi"` |  |
| vpa.components.backendWorker.enabled | bool | `true` |  |
| vpa.components.backendWorker.maxAllowed.cpu | int | `1` |  |
| vpa.components.backendWorker.maxAllowed.memory | string | `"12Gi"` |  |
| vpa.components.backendWorker.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.backendWorker.minAllowed.memory | string | `"600Mi"` |  |
| vpa.components.blockBuilder.enabled | bool | `true` |  |
| vpa.components.blockBuilder.maxAllowed.cpu | int | `2` |  |
| vpa.components.blockBuilder.maxAllowed.memory | string | `"8Gi"` |  |
| vpa.components.blockBuilder.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.blockBuilder.minAllowed.memory | string | `"200Mi"` |  |
| vpa.components.distributor.enabled | bool | `true` |  |
| vpa.components.distributor.maxAllowed.cpu | int | `1` |  |
| vpa.components.distributor.maxAllowed.memory | string | `"2Gi"` |  |
| vpa.components.distributor.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.distributor.minAllowed.memory | string | `"50Mi"` |  |
| vpa.components.gateway.enabled | bool | `true` |  |
| vpa.components.gateway.maxAllowed.cpu | int | `1` |  |
| vpa.components.gateway.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.gateway.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.gateway.minAllowed.memory | string | `"100Mi"` |  |
| vpa.components.liveStore.enabled | bool | `true` |  |
| vpa.components.liveStore.maxAllowed.cpu | int | `2` |  |
| vpa.components.liveStore.maxAllowed.memory | string | `"8Gi"` |  |
| vpa.components.liveStore.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.liveStore.minAllowed.memory | string | `"200Mi"` |  |
| vpa.components.metricsGenerator.enabled | bool | `true` |  |
| vpa.components.metricsGenerator.maxAllowed.cpu | int | `1` |  |
| vpa.components.metricsGenerator.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.metricsGenerator.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.metricsGenerator.minAllowed.memory | string | `"100Mi"` |  |
| vpa.components.querier.enabled | bool | `true` |  |
| vpa.components.querier.maxAllowed.cpu | int | `1` |  |
| vpa.components.querier.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.querier.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.querier.minAllowed.memory | string | `"100Mi"` |  |
| vpa.components.queryFrontend.enabled | bool | `true` |  |
| vpa.components.queryFrontend.maxAllowed.cpu | int | `1` |  |
| vpa.components.queryFrontend.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.queryFrontend.minAllowed.cpu | string | `"10m"` |  |
| vpa.components.queryFrontend.minAllowed.memory | string | `"100Mi"` |  |
| vpa.enabled | bool | `true` | Enable VPA resources for Tempo components |
| vpa.updateMode | string | `"Auto"` | VPA update mode (e.g. Off, Initial, Auto, InPlaceOrRecreate) |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)

