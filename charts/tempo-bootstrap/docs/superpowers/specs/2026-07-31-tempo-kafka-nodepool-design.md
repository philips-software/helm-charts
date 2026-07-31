# Design Document: Tempo Bootstrap Kafka Integration & Dedicated NodePool

- **Date**: 2026-07-31
- **Chart**: `charts/tempo-bootstrap`
- **Target Tempo Chart**: `tempo-distributed` version 3.0.6 (Grafana Tempo 3.0)

## 1. Overview

Grafana Tempo 3.0 (microservices mode) introduces a Kafka-backed write path architecture where distributors write incoming trace data into Kafka, and `blockBuilder` and `liveStore` components consume spans from Kafka partitions. 

This design document specifies the integration of Kafka and a dedicated Karpenter `NodePool` into `tempo-bootstrap`, aligning with the architecture used in `mimir-bootstrap` while maintaining isolation for Tempo workloads.

## 2. Architecture & Components

```
                     +----------------------+
                     |  OTLP / Ingest Spans |
                     +----------+-----------+
                                |
                                v
                     +----------------------+
                     |  tempo-distributor   |
                     +----------+-----------+
                                |
                                v
                   +--------------------------+
                   |  tempo-kafka (StatefulSet)|  <-- Runs on tempo-kafka-nodepool
                   +----+-----------------+---+
                        |                 |
                        v                 v
             +------------------+  +------------------+
             | tempo-blockBuilder |  |  tempo-liveStore  |
             +--------+---------+  +------------------+
                      |
                      v
             +------------------+
             |   S3 Storage     |
             +------------------+
```

### 2.1 Dedicated Karpenter NodePool (`tempo-kafka-nodepool`)
- **File**: `charts/tempo-bootstrap/templates/kafka-nodepool.yaml`
- **Resource**: `karpenter.sh/v1` `NodePool`
- **Metadata Name**: `tempo-kafka-nodepool`
- **Labels**: `workload: tempo-kafka`
- **Taints**: `workload=tempo-kafka:NoSchedule` (reserves nodes exclusively for Tempo Kafka workloads)
- **NodeClass Reference**: `bottlerocket-v2` (configurable via `.Values.kafkaNodePool.nodeClassRefName`)
- **Limits**: Configurable via `.Values.kafkaNodePool.resources.limits` (default 4 CPU, 16Gi Memory).

### 2.2 Tempo Kafka StatefulSet (`tempo-kafka`)
- **File**: `charts/tempo-bootstrap/templates/tempo-kafka.yaml`
- **Namespace**: `tempo-system`
- **Image**: `docker.io/apache/kafka-native:4.1.0` (KRaft mode without Zookeeper)
- **Persistence**: 100Gi PVC (`kafka.persistence.size`), mounted at `/var/lib/kafka/data`
- **Services**:
  - `tempo-kafka` (ClusterIP, port 9092)
  - `tempo-kafka-headless` (Headless ClusterIP, ports 9092, 9093)
- **Placement**:
  - `nodeSelector`: `workload: tempo-kafka`
  - `tolerations`: `workload=tempo-kafka:NoSchedule`
  - `podAnnotations`: `karpenter.sh/do-not-disrupt: "true"` if Karpenter consolidation disruption prevention is enabled.

### 2.3 Tempo Configuration Update (`config/tempo-values.yaml`)
- **Kafka Ingestion**:
  ```yaml
  ingest:
    kafka:
      address: "tempo-kafka.tempo-system.svc.cluster.local:9092"
      topic: "tempo-traces"
      auto_create_topic_enabled: true
      auto_create_topic_default_partitions: 3
  ```
- **BlockBuilder & LiveStore**:
  - Enable `blockBuilder` with 3 replicas (matching 3 topic partitions).
  - Enable `liveStore` with 3 replicas.
  - Remove obsolete top-level `ingester` block.

### 2.4 Vertical Pod Autoscalers (VPAs)
- Remove `templates/ingester-vpa.yaml`
- Create `templates/block-builder-vpa.yaml` targeting Deployment/StatefulSet `tempo-block-builder`
- Create `templates/live-store-vpa.yaml` targeting Deployment/StatefulSet `tempo-live-store`

### 2.5 Values Schema (`values.yaml`)
Add configuration defaults:
```yaml
kafka:
  persistence:
    size: 100Gi

kafkaNodePool:
  enabled: true
  labels:
    workload: tempo-kafka
  nodeClassRefName: bottlerocket-v2
  resources:
    limits:
      cpu: 4
      memory: 16Gi
  expireAfter: 3600h
```

## 3. Verification Plan

1. Render chart templates via `helm template` to ensure valid K8s syntax and schema correctness.
2. Generate documentation via `helm-docs`.
3. Verify git diff for clean configuration and accurate wiring.
