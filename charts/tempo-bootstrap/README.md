# tempo

![Version: 0.43.12](https://img.shields.io/badge/Version-0.43.12-informational?style=flat-square)

# Deployment

## Using helm

```shell
helm upgrade --install oci://ghcr.io/philips-software/helm-charts/tempo-bootstrap:0.43.12 -n monitoring
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
| kafka.persistence.size | string | `"100Gi"` |  |
| kafkaNodePool.consolidationPolicy | string | `"WhenEmpty"` |  |
| kafkaNodePool.enabled | bool | `true` |  |
| kafkaNodePool.expireAfter | string | `"3600h"` |  |
| kafkaNodePool.labels.workload | string | `"tempo-kafka"` |  |
| kafkaNodePool.nodeClassRefName | string | `"bottlerocket-v2"` |  |
| kafkaNodePool.resources.limits.cpu | int | `4` |  |
| kafkaNodePool.resources.limits.memory | string | `"16Gi"` |  |
| kafkaNodePool.taintKey | string | `"cilium.hsp.philips.com/dedicated"` |  |
| liveStore.replicas | int | `3` | Number of live-store replicas |
| multitenancyEnabled | bool | `true` |  |
| querier.replicas | int | `2` | Number of querier replicas |
| queryFrontend.replicas | int | `2` | Number of query-frontend replicas |
| streamOverHTTPEnabled | bool | `true` |  |
| tempoChart.version | string | `"3.11.0"` |  |
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

