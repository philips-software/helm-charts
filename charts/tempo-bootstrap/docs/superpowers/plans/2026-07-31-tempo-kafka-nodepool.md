# Tempo Bootstrap Kafka Integration & Dedicated NodePool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Kafka and a dedicated Karpenter NodePool (`tempo-kafka-nodepool`) into `tempo-bootstrap` for Tempo 3.0 microservices mode.

**Architecture:** Create `templates/kafka-nodepool.yaml` (NodePool for `workload: tempo-kafka`), `templates/tempo-kafka.yaml` (StatefulSet & Service for Kafka native broker), update `config/tempo-values.yaml` to wire `ingest.kafka.address`, `blockBuilder`, and `liveStore`, and update VPAs.

**Tech Stack:** Helm 3, Kubernetes, Karpenter `NodePool`, Apache Kafka (`apache/kafka-native:4.1.0`), Grafana Tempo 3.0 (`tempo-distributed` chart 3.0.6), `helm-docs`.

## Global Constraints

- **NodePool Name**: `tempo-kafka-nodepool`
- **Workload Label**: `workload: tempo-kafka`
- **Taint**: `workload=tempo-kafka:NoSchedule`
- **Kafka Image**: `docker.io/apache/kafka-native:4.1.0`
- **Namespace**: `tempo-system`

---

### Task 1: Add Kafka & NodePool Configuration to values.yaml

**Files:**
- Modify: `charts/tempo-bootstrap/values.yaml`

- [ ] **Step 1: Update `values.yaml` with Kafka & KafkaNodePool blocks**

Add the `kafka` and `kafkaNodePool` values to `charts/tempo-bootstrap/values.yaml`:

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
  expireAfter: 3600h  # half a year
```

- [ ] **Step 2: Commit changes**

```bash
git add charts/tempo-bootstrap/values.yaml
git commit -m "feat(tempo-bootstrap): add kafka and kafkaNodePool configuration values"
```

---

### Task 2: Create NodePool Template for Tempo Kafka

**Files:**
- Create: `charts/tempo-bootstrap/templates/kafka-nodepool.yaml`

- [ ] **Step 1: Create `templates/kafka-nodepool.yaml`**

```yaml
{{- if .Values.kafkaNodePool.enabled }}
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: tempo-kafka-nodepool
spec:
  disruption:
    budgets:
    - nodes: 10%
    consolidateAfter: 300s
    consolidationPolicy: WhenEmptyOrUnderutilized
  limits:
    amd.com/gpu: 0
    aws.amazon.com/neuron: 0
    cpu: {{ .Values.kafkaNodePool.resources.limits.cpu }}
    memory: {{ .Values.kafkaNodePool.resources.limits.memory }}
    nvidia.com/gpu: 0
  template:
    metadata:
      labels:
        {{- range $key, $value := .Values.kafkaNodePool.labels }}
        {{ $key }}: {{ $value }}
        {{- end }}
    spec:
      expireAfter: {{ .Values.kafkaNodePool.expireAfter }}
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: {{ .Values.kafkaNodePool.nodeClassRefName }}
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - on-demand
      - key: karpenter.k8s.aws/instance-hypervisor
        operator: In
        values:
        - nitro
      - key: kubernetes.io/arch
        operator: In
        values:
        - arm64
      - key: karpenter.k8s.aws/instance-family
        operator: NotIn
        values:
        - a1
      - key: karpenter.k8s.aws/instance-memory
        operator: Gt
        values:
        - "4000"
      - key: karpenter.k8s.aws/instance-cpu
        operator: Gt
        values:
        - "1"
      # Permanent taints to reserve nodes for tempo kafka workloads only
      taints:
      - effect: NoSchedule
        key: workload
        value: tempo-kafka
      terminationGracePeriod: 24h
  weight: 5
{{- end }}
```

- [ ] **Step 2: Commit changes**

```bash
git add charts/tempo-bootstrap/templates/kafka-nodepool.yaml
git commit -m "feat(tempo-bootstrap): add dedicated tempo-kafka-nodepool template"
```

---

### Task 3: Create Tempo Kafka Broker StatefulSet & Services

**Files:**
- Create: `charts/tempo-bootstrap/templates/tempo-kafka.yaml`

- [ ] **Step 1: Create `templates/tempo-kafka.yaml`**

```yaml
{{- if .Values.kafkaNodePool.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: tempo-kafka
  namespace: tempo-system
  labels:
    app.kubernetes.io/name: tempo-kafka
    app.kubernetes.io/component: kafka
spec:
  type: ClusterIP
  ports:
    - port: 9092
      protocol: TCP
      name: kafka
      targetPort: kafka
  selector:
    app.kubernetes.io/name: tempo-kafka
    app.kubernetes.io/component: kafka
---
apiVersion: v1
kind: Service
metadata:
  name: tempo-kafka-headless
  namespace: tempo-system
  labels:
    app.kubernetes.io/name: tempo-kafka
    app.kubernetes.io/component: kafka
spec:
  type: ClusterIP
  clusterIP: None
  publishNotReadyAddresses: true
  ports:
    - port: 9092
      protocol: TCP
      name: kafka
      targetPort: kafka
    - port: 9093
      protocol: TCP
      name: controller
      targetPort: controller
  selector:
    app.kubernetes.io/name: tempo-kafka
    app.kubernetes.io/component: kafka
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tempo-kafka
  namespace: tempo-system
  labels:
    app.kubernetes.io/name: tempo-kafka
    app.kubernetes.io/component: kafka
spec:
  podManagementPolicy: Parallel
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: tempo-kafka
      app.kubernetes.io/component: kafka
  serviceName: tempo-kafka-headless
  template:
    metadata:
      labels:
        app.kubernetes.io/name: tempo-kafka
        app.kubernetes.io/component: kafka
    spec:
      securityContext:
        fsGroup: 1001
        runAsGroup: 1001
        runAsNonRoot: true
        runAsUser: 1001
        seccompProfile:
          type: RuntimeDefault
      terminationGracePeriodSeconds: 30
      nodeSelector:
        {{- range $key, $value := .Values.kafkaNodePool.labels }}
        {{ $key }}: {{ $value }}
        {{- end }}
      tolerations:
      - key: workload
        operator: Equal
        value: tempo-kafka
        effect: NoSchedule
      containers:
        - name: kafka
          image: docker.io/apache/kafka-native:4.1.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 9092
              name: kafka
              protocol: TCP
            - containerPort: 9093
              name: controller
              protocol: TCP
          env:
            - name: _POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: KAFKA_CLUSTER_ID
              value: "TempoKafkaCluster001"
            - name: KAFKA_NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['apps.kubernetes.io/pod-index']
            - name: KAFKA_PROCESS_ROLES
              value: broker,controller
            - name: KAFKA_LISTENERS
              value: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
            - name: KAFKA_ADVERTISED_LISTENERS
              value: PLAINTEXT://$(_POD_NAME).tempo-kafka-headless.tempo-system.svc.cluster.local:9092
            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: 0@tempo-kafka-0.tempo-kafka-headless.tempo-system.svc.cluster.local:9093
            - name: KAFKA_CONTROLLER_LISTENER_NAMES
              value: CONTROLLER
            - name: KAFKA_INTER_BROKER_LISTENER_NAME
              value: PLAINTEXT
            - name: KAFKA_LOG_DIRS
              value: /var/lib/kafka/data
            - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
              value: "1"
            - name: KAFKA_AUTO_CREATE_TOPICS_ENABLE
              value: "true"
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              memory: 1Gi
          volumeMounts:
            - mountPath: /var/lib/kafka/data
              name: data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: {{ .Values.kafka.persistence.size }}
{{- end }}
```

- [ ] **Step 2: Commit changes**

```bash
git add charts/tempo-bootstrap/templates/tempo-kafka.yaml
git commit -m "feat(tempo-bootstrap): add tempo-kafka StatefulSet and Service templates"
```

---

### Task 4: Update tempo-values.yaml for Tempo 3.0 & Kafka Wiring

**Files:**
- Modify: `charts/tempo-bootstrap/config/tempo-values.yaml`

- [ ] **Step 1: Update `tempo-values.yaml`**

Replace `ingester:` section with `blockBuilder:` and `liveStore:`, and add `ingest.kafka:`:

```yaml
ingest:
  kafka:
    address: "tempo-kafka.tempo-system.svc.cluster.local:9092"
    topic: "tempo-traces"
    auto_create_topic_enabled: true
    auto_create_topic_default_partitions: 3

blockBuilder:
  enabled: true
  replicas: 3
  resources:
    requests:
      cpu: "120m"
      memory: "800Mi"
    limits:
      memory: "1200Mi"
  extraArgs:
    - -config.expand-env=true
  extraEnv:
    - name: S3_BUCKET_NAME
      valueFrom:
        secretKeyRef:
          name: {{ .Values.environmentConfig.resourcePrefix }}-tempo
          key: id

liveStore:
  enabled: true
  replicas: 3
  resources:
    requests:
      cpu: "120m"
      memory: "800Mi"
    limits:
      memory: "1200Mi"
  extraArgs:
    - -config.expand-env=true
  extraEnv:
    - name: S3_BUCKET_NAME
      valueFrom:
        secretKeyRef:
          name: {{ .Values.environmentConfig.resourcePrefix }}-tempo
          key: id
```

Remove the old `ingester:` block (lines 17-31).

- [ ] **Step 2: Commit changes**

```bash
git add charts/tempo-bootstrap/config/tempo-values.yaml
git commit -m "feat(tempo-bootstrap): configure ingest.kafka, blockBuilder, and liveStore for Tempo 3.0"
```

---

### Task 5: Update VPAs for BlockBuilder and LiveStore

**Files:**
- Delete: `charts/tempo-bootstrap/templates/ingester-vpa.yaml`
- Create: `charts/tempo-bootstrap/templates/block-builder-vpa.yaml`
- Create: `charts/tempo-bootstrap/templates/live-store-vpa.yaml`

- [ ] **Step 1: Delete `ingester-vpa.yaml`**

```bash
git rm charts/tempo-bootstrap/templates/ingester-vpa.yaml
```

- [ ] **Step 2: Create `templates/block-builder-vpa.yaml`**

```yaml
apiVersion: "autoscaling.k8s.io/v1"
kind: VerticalPodAutoscaler
metadata:
  name: tempo-block-builder-vpa
  namespace: tempo-system
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: StatefulSet
    name: tempo-block-builder
  updatePolicy:
    minReplicas: 1
    updateMode: Auto
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        minAllowed:
          cpu: 10m
          memory: 200Mi
        maxAllowed:
          cpu: 2
          memory: 8Gi
        controlledResources: ["memory", "cpu"]
```

- [ ] **Step 3: Create `templates/live-store-vpa.yaml`**

```yaml
apiVersion: "autoscaling.k8s.io/v1"
kind: VerticalPodAutoscaler
metadata:
  name: tempo-live-store-vpa
  namespace: tempo-system
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: StatefulSet
    name: tempo-live-store
  updatePolicy:
    minReplicas: 1
    updateMode: Auto
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        minAllowed:
          cpu: 10m
          memory: 200Mi
        maxAllowed:
          cpu: 2
          memory: 8Gi
        controlledResources: ["memory", "cpu"]
```

- [ ] **Step 4: Commit changes**

```bash
git add charts/tempo-bootstrap/templates/
git commit -m "feat(tempo-bootstrap): replace ingester-vpa with block-builder-vpa and live-store-vpa"
```

---

### Task 6: Documentation & Validation

**Files:**
- Modify: `charts/tempo-bootstrap/README.md.gotmpl`
- Modify: `charts/tempo-bootstrap/README.md`

- [ ] **Step 1: Update README.md.gotmpl**

Ensure `README.md.gotmpl` includes values table rendering.

- [ ] **Step 2: Run helm-docs**

```bash
helm-docs -c charts/tempo-bootstrap
```

- [ ] **Step 3: Verify helm rendering**

```bash
helm template test charts/tempo-bootstrap --set existingBucketName=my-bucket --set environmentConfig.resourcePrefix=test --set environmentConfig.region=us-east-1 --set environmentConfig.accountId=123456789012
```

- [ ] **Step 4: Commit documentation & final validation changes**

```bash
git add charts/tempo-bootstrap/
git commit -m "docs(tempo-bootstrap): update README with kafka and kafkaNodePool configuration"
```
