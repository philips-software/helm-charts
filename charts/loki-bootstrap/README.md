# loki-bootstrap

![Version: 0.46.2](https://img.shields.io/badge/Version-0.46.2-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argoProject | string | `"default"` |  |
| compactor.replicas | int | `1` |  |
| compactorOrgmapper.package | string | `"ghcr.io/loafoe/compactor-orgmapper"` |  |
| compactorOrgmapper.tag | string | `"v0.0.1"` |  |
| distributor.replicas | int | `3` |  |
| distributor.resources.limits.memory | string | `"2Gi"` |  |
| distributor.resources.requests.cpu | string | `"250m"` |  |
| distributor.resources.requests.memory | string | `"1Gi"` |  |
| environmentConfig.accountId | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| existingBucketName | string | `""` |  |
| extraResourceAttributesAsIndexLabels | list | `[]` |  |
| features.cloudwatchKillJob | bool | `false` |  |
| gateway.replicas | int | `3` |  |
| gateway.resources.limits.memory | string | `"128Mi"` |  |
| gateway.resources.requests.cpu | string | `"50m"` |  |
| gateway.resources.requests.memory | string | `"64Mi"` |  |
| indexGateway.replicas | int | `3` |  |
| ingester.replicas | int | `3` |  |
| ingester.resources.limits.memory | string | `"10Gi"` |  |
| ingester.resources.requests.cpu | string | `"500m"` |  |
| ingester.resources.requests.memory | string | `"8Gi"` |  |
| initOverrides.package | string | `"busybox"` |  |
| initOverrides.tag | string | `"1.38.0"` |  |
| loki.limits_config.max_entries_limit_per_query | int | `5000` |  |
| loki.limits_config.max_global_streams_per_user | int | `5000` |  |
| loki.limits_config.max_label_names_per_series | int | `18` |  |
| loki.limits_config.max_query_series | int | `500` |  |
| loki.pattern_ingester.client_config.grpc_client_config.max_recv_msg_size | int | `83886080` |  |
| loki.pattern_ingester.client_config.grpc_client_config.max_send_msg_size | int | `83886080` |  |
| loki.pattern_ingester.enabled | bool | `true` |  |
| loki.replicationFactor | int | `2` |  |
| loki.server.grpc_server_max_concurrent_streams | int | `1000` |  |
| loki.server.grpc_server_max_recv_msg_size | int | `83886080` |  |
| loki.server.grpc_server_max_send_msg_size | int | `83886080` |  |
| lokiChart.version | string | `"19.0.0"` |  |
| multitenancyEnabled | bool | `true` |  |
| patternIngester.extraArgs.grpc_max_recv_msg_size | int | `83886080` |  |
| patternIngester.extraArgs.grpc_max_send_msg_size | int | `83886080` |  |
| patternIngester.replicas | int | `3` |  |
| patternIngester.resources.limits.memory | string | `"1Gi"` |  |
| patternIngester.resources.requests.cpu | string | `"50m"` |  |
| patternIngester.resources.requests.memory | string | `"512Mi"` |  |
| priorityClass | object | `{"enabled":true,"name":"loki-stateful","value":1000000}` | PriorityClass for the stateful write path (ingesters): these hold not-yet-flushed data, so if they are evicted or left Pending on a full node, ingestion stalls and un-replicated data is at risk. Without it they run at the default priority 0, the same as every stateless query/read pod, and can be preempted by (or fail to preempt) any of them. The value sits well below the built-in system-node-critical/system-cluster-critical classes, so node agents and cluster add-ons still win. Created by this chart with a chart-specific name, so it does not clash with the loki/mimir/tempo-bootstrap siblings. Note: a PriorityClass value is immutable; to change it, also change the name. |
| querier.replicas | int | `6` |  |
| querier.resources.limits.memory | string | `"250Mi"` |  |
| querier.resources.requests.cpu | string | `"20m"` |  |
| querier.resources.requests.memory | string | `"150Mi"` |  |
| queryFrontend.replicas | int | `3` |  |
| queryFrontend.resources.limits.memory | string | `"512Mi"` |  |
| queryFrontend.resources.requests.cpu | string | `"10m"` |  |
| queryFrontend.resources.requests.memory | string | `"256Mi"` |  |
| queryScheduler.replicas | int | `3` |  |
| ruler.replicas | int | `3` |  |
| vpa.components.compactor.enabled | bool | `true` |  |
| vpa.components.compactor.maxAllowed.memory | string | `"1Gi"` |  |
| vpa.components.compactor.minAllowed.memory | string | `"128Mi"` |  |
| vpa.components.distributor.enabled | bool | `true` |  |
| vpa.components.distributor.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.distributor.minAllowed.memory | string | `"1Gi"` |  |
| vpa.components.gateway.enabled | bool | `true` |  |
| vpa.components.gateway.maxAllowed.memory | string | `"256Mi"` |  |
| vpa.components.gateway.minAllowed.memory | string | `"64Mi"` |  |
| vpa.components.indexGateway.enabled | bool | `true` |  |
| vpa.components.indexGateway.maxAllowed.memory | string | `"1Gi"` |  |
| vpa.components.indexGateway.minAllowed.memory | string | `"128Mi"` |  |
| vpa.components.ingester.enabled | bool | `true` |  |
| vpa.components.ingester.maxAllowed.memory | string | `"16Gi"` |  |
| vpa.components.ingester.minAllowed.memory | string | `"8Gi"` |  |
| vpa.components.patternIngester.enabled | bool | `true` |  |
| vpa.components.patternIngester.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.patternIngester.minAllowed.memory | string | `"512Mi"` |  |
| vpa.components.querier.enabled | bool | `true` |  |
| vpa.components.querier.maxAllowed.memory | string | `"4Gi"` |  |
| vpa.components.querier.minAllowed.memory | string | `"150Mi"` |  |
| vpa.enabled | bool | `false` |  |
| vpa.updateMode | string | `"InPlaceOrRecreate"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
