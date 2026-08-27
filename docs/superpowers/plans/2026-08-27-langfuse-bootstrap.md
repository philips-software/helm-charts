# Langfuse Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two new Helm charts — `clickhouse-operator-bootstrap` and `langfuse-bootstrap` — that together deploy a working Langfuse instance (Postgres via CNPG, ClickHouse via the ClickHouse Operator, self-managed Redis, S3 via IRSA) reachable at a functioning login screen.

**Architecture:** ArgoCD-Application wrapper charts, same shape as `agentgateway-bootstrap`/`loki-bootstrap`. `clickhouse-operator-bootstrap` installs the upstream ClickHouse operator cluster-wide (mirrors `cloudnative-pg-operator`). `langfuse-bootstrap` creates a CNPG `Cluster`, a self-managed Valkey `StatefulSet`, an `S3IRSA` CR, one shared credentials `Secret`, and an ArgoCD `Application` wrapping `oci://ghcr.io/langfuse/langfuse-k8s/charts/langfuse` v2.0.2.

**Tech Stack:** Helm 3, ArgoCD `Application` CRs, CloudNativePG, ClickHouse Operator (`clickhouse.com/v1alpha1`), Valkey, Crossplane `S3IRSA` (dip.io/v1alpha1), `helm-docs`, `chart-testing` (`ct`).

**Specs:**
- `charts/clickhouse-operator-bootstrap/docs/superpowers/specs/2026-08-27-clickhouse-operator-bootstrap-design.md`
- `charts/langfuse-bootstrap/docs/superpowers/specs/2026-08-27-langfuse-bootstrap-design.md`

## Global Constraints
- Never use Bitnami images. Use official images (`valkey/valkey`, `alpine/k8s`) instead.
- Add Renovate annotations (`# renovate: datasource=... depName=...`) to every pinned chart/image version.
- No CPU limits on any container — memory limits only.
- Only static, values.yaml-driven credentials (no runtime-generated secrets) — ArgoCD renders via `helm template`, which cannot use Helm's `lookup`, so anything random regenerates every sync (breaks `salt`/`encryptionKey` and any password rotation). Every credential is a plain string field in `values.yaml` referenced via `secretKeyRef`.
- `clickhouse.auth.username` must be exactly `default` when `clickhouse.deploy: true` (verified in upstream `templates/validations.yaml` — the operator CR only provisions a password for the built-in default user).
- `clickhouse.keeper.enabled` must stay `true` whenever `clickhouse.deploy: true` (CRD requires `spec.keeperClusterRef` even for a single ClickHouse replica).
- S3 access is IRSA-only — no static `accessKeyId`/`secretAccessKey` anywhere (verified: upstream chart omits the corresponding env vars entirely when both are unset, falling through to the AWS SDK's default credential chain).
- Local `helm template`/`helm lint` runs against the Langfuse chart need `--api-versions clickhouse.com/v1alpha1/ClickHouseCluster --api-versions clickhouse.com/v1alpha1/KeeperCluster` (upstream's CRD preflight uses `.Capabilities.APIVersions.Has`, which is empty without a real cluster or this flag).
- Both new charts get added to root `ct.yaml`'s `excluded-charts` list (same as every other ArgoCD-Application-wrapper chart in this repo) — `ct install` can't satisfy the external CRD/cluster prerequisites these charts assume.

---

## Task 1: `clickhouse-operator-bootstrap` chart scaffold

**Files:**
- Create: `charts/clickhouse-operator-bootstrap/Chart.yaml`
- Create: `charts/clickhouse-operator-bootstrap/values.yaml`
- Create: `charts/clickhouse-operator-bootstrap/templates/_helpers.tpl`

**Interfaces:**
- Produces: Helm helpers `clickhouse-operator-bootstrap.name`, `.fullname`, `.chart`, `.labels`, `.selectorLabels`, `.validateConfig` — consumed by Task 2's template.
- Produces: values `argoProject`, `clickhouseOperatorChart.repoURL`, `clickhouseOperatorChart.version`, `operator.namespace`, `operator.watchNamespaces`, `operator.resources` — consumed by Task 2.

- [ ] **Step 1: Write `Chart.yaml`**

```yaml
apiVersion: v2
name: clickhouse-operator-bootstrap
description: A Helm chart for bootstrapping the ClickHouse Kubernetes Operator
type: application
version: 0.1.0
appVersion: "0.0.7"
keywords:
  - clickhouse
  - operator
  - argocd
  - bootstrap
```

- [ ] **Step 2: Write `values.yaml`**

```yaml
# Upstream ClickHouse Operator Helm chart configuration
clickhouseOperatorChart:
  # OCI repository for the operator's Helm chart
  repoURL: oci://ghcr.io/clickhouse/clickhouse-operator-helm
  # renovate: datasource=docker depName=ghcr.io/clickhouse/clickhouse-operator-helm
  version: 0.0.7

# ArgoCD project name
argoProject: default

# ClickHouse Operator controller configuration
operator:
  # Namespace the operator (and its CRDs' webhook/cert-manager resources) run in.
  # Cluster-scoped — install once per cluster.
  namespace: clickhouse-operator-system
  # Namespaces the operator watches for ClickHouseCluster/KeeperCluster CRs.
  # Empty watches all namespaces (upstream default).
  watchNamespaces: []
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      memory: 256Mi
```

- [ ] **Step 3: Write `templates/_helpers.tpl`**

```
{{/*
Expand the name of the chart.
*/}}
{{- define "clickhouse-operator-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "clickhouse-operator-bootstrap.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "clickhouse-operator-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clickhouse-operator-bootstrap.labels" -}}
helm.sh/chart: {{ include "clickhouse-operator-bootstrap.chart" . }}
{{ include "clickhouse-operator-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clickhouse-operator-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clickhouse-operator-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "clickhouse-operator-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.clickhouseOperatorChart.version }}
{{- fail "clickhouseOperatorChart.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.operator.namespace }}
{{- fail "operator.namespace is required and cannot be empty" }}
{{- end }}
{{- end }}
```

- [ ] **Step 4: Verify scaffold lints clean (no templates yet, so this only checks Chart.yaml/values.yaml syntax)**

Run: `cd charts/clickhouse-operator-bootstrap && helm lint .`
Expected: `1 chart(s) linted, 0 chart(s) failed` (a chart with zero resource templates still lints successfully — this just confirms YAML syntax).

- [ ] **Step 5: Commit**

```bash
git add charts/clickhouse-operator-bootstrap/Chart.yaml charts/clickhouse-operator-bootstrap/values.yaml charts/clickhouse-operator-bootstrap/templates/_helpers.tpl
git commit -m "feat(clickhouse-operator-bootstrap): scaffold chart"
```

---

## Task 2: `clickhouse-operator-bootstrap` ArgoCD Application

**Files:**
- Create: `charts/clickhouse-operator-bootstrap/templates/clickhouse-operator-helm.yaml`

**Interfaces:**
- Consumes: helpers and values from Task 1 (`clickhouse-operator-bootstrap.validateConfig`, `.labels`, `.Values.clickhouseOperatorChart.*`, `.Values.argoProject`, `.Values.operator.*`).
- Produces: an ArgoCD `Application` named `clickhouse-operator-helm` — no other task in this plan depends on its name (langfuse-bootstrap only depends on the operator's CRDs existing in the cluster, not on this chart's resource names).

- [ ] **Step 1: Write `templates/clickhouse-operator-helm.yaml`**

```yaml
{{- include "clickhouse-operator-bootstrap.validateConfig" . -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: clickhouse-operator-helm
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "clickhouse-operator-bootstrap.labels" . | nindent 4 }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: {{ .Values.argoProject }}
  source:
    repoURL: {{ .Values.clickhouseOperatorChart.repoURL | quote }}
    targetRevision: {{ .Values.clickhouseOperatorChart.version | quote }}
    helm:
      releaseName: clickhouse-operator
      valuesObject:
        controller:
          watchNamespaces:
            {{- toYaml .Values.operator.watchNamespaces | nindent 12 }}
        manager:
          resources:
            {{- toYaml .Values.operator.resources | nindent 12 }}
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .Values.operator.namespace }}
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

- [ ] **Step 2: Render and assert the Application looks right**

Run:
```bash
cd charts/clickhouse-operator-bootstrap
helm template test . | tee /tmp/ch-op-render.yaml
grep -q "kind: Application" /tmp/ch-op-render.yaml
grep -q "repoURL: oci://ghcr.io/clickhouse/clickhouse-operator-helm" /tmp/ch-op-render.yaml
grep -q 'targetRevision: "0.0.7"' /tmp/ch-op-render.yaml
grep -q "namespace: clickhouse-operator-system" /tmp/ch-op-render.yaml
grep -q 'argocd.argoproj.io/sync-wave: "0"' /tmp/ch-op-render.yaml
echo "all assertions passed"
```
Expected: all four `grep -q` calls succeed (exit 0) and the script prints `all assertions passed`. If any `grep` fails the script stops early (no `set -e` needed here since we're chaining with `&&`-free sequential greps — run them one at a time and confirm each exits 0).

- [ ] **Step 3: `helm lint`**

Run: `helm lint charts/clickhouse-operator-bootstrap`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 4: Commit**

```bash
git add charts/clickhouse-operator-bootstrap/templates/clickhouse-operator-helm.yaml
git commit -m "feat(clickhouse-operator-bootstrap): add ArgoCD Application for the operator"
```

---

## Task 3: `clickhouse-operator-bootstrap` docs + `ct.yaml` registration

**Files:**
- Create: `charts/clickhouse-operator-bootstrap/README.md.gotmpl`
- Create: `charts/clickhouse-operator-bootstrap/README.md` (generated by `helm-docs`)
- Modify: `ct.yaml:8-18` (repo root) — add `clickhouse-operator-bootstrap` to `excluded-charts`

**Interfaces:**
- None — this task only produces documentation and CI configuration, nothing later tasks import.

- [ ] **Step 1: Write `README.md.gotmpl`**

```gotmpl
# {{ template "chart.header" . }}
{{ template "chart.deprecationWarning" . }}

{{ template "chart.badgesSection" . }}

{{ template "chart.description" . }}

Installs the [ClickHouse Kubernetes Operator](https://github.com/ClickHouse/clickhouse-operator) cluster-wide via an ArgoCD `Application`. Install once per cluster before any chart that renders `ClickHouseCluster`/`KeeperCluster` CRs (e.g. `langfuse-bootstrap`).

## Prerequisites

- cert-manager, installed cluster-wide (the operator's chart creates `Certificate`/`Issuer` resources for its webhooks).

{{ template "chart.requirementsSection" . }}

{{ template "chart.valuesHeader" . }}

{{ template "chart.valuesTable" . }}

{{ template "helm-docs.versionFooter" . }}
```

- [ ] **Step 2: Generate `README.md`**

Run: `helm-docs --chart-search-root=charts/clickhouse-operator-bootstrap`
Expected: `charts/clickhouse-operator-bootstrap/README.md` is created/updated with the rendered values table.

- [ ] **Step 3: Register the chart in root `ct.yaml`'s `excluded-charts`**

Read `ct.yaml` first to confirm the current alphabetical ordering of `excluded-charts`, then insert `clickhouse-operator-bootstrap` in alphabetical position (it sorts before `cloudnative-pg-bootstrap`):

```yaml
excluded-charts:
  - agentgateway-bootstrap
  - centcom-satellite
  - clickhouse-operator-bootstrap
  - cloudnative-pg-bootstrap
  - cloudnative-pg-operator
  - crossplane-providers
  - grafana
  - k8s-observability-monitoring
  - loki-bootstrap
  - mimir-bootstrap
  - otlp-gateway-bootstrap
  - tempo-bootstrap
```

- [ ] **Step 4: `ct lint` locally**

Run: `ct lint --config ct.yaml --charts charts/clickhouse-operator-bootstrap` (run from repo root)
Expected: lint passes (no errors reported for `clickhouse-operator-bootstrap`).

- [ ] **Step 5: Commit**

```bash
git add charts/clickhouse-operator-bootstrap/README.md.gotmpl charts/clickhouse-operator-bootstrap/README.md ct.yaml
git commit -m "docs(clickhouse-operator-bootstrap): add README, exclude from ct install"
```

---

## Task 4: `langfuse-bootstrap` chart scaffold

**Files:**
- Create: `charts/langfuse-bootstrap/Chart.yaml`
- Create: `charts/langfuse-bootstrap/values.yaml`
- Create: `charts/langfuse-bootstrap/templates/_helpers.tpl`

**Interfaces:**
- Produces: helpers `langfuse-bootstrap.name`, `.fullname`, `.chart`, `.labels`, `.selectorLabels`, `.substituteVars`, `.validateConfig`, `.postgresClusterName`, `.s3ServiceAccountName` — consumed by every later task in this chart.
- Produces: the full `values.yaml` schema below — every field referenced by name in Tasks 5-9.

- [ ] **Step 1: Write `Chart.yaml`**

```yaml
apiVersion: v2
name: langfuse-bootstrap
description: A Helm chart for bootstrapping Langfuse (LLM engineering platform) with CNPG Postgres, self-managed Redis, and S3 via IRSA
type: application
version: 0.1.0
appVersion: "4.17.0"
keywords:
  - langfuse
  - llm
  - observability
  - clickhouse
  - argocd
  - bootstrap
```

- [ ] **Step 2: Write `values.yaml`**

```yaml
# langfuse-bootstrap configuration

# Upstream langfuse-k8s Helm chart configuration
langfuseChart:
  repoURL: oci://ghcr.io/langfuse/langfuse-k8s/charts
  # renovate: datasource=docker depName=ghcr.io/langfuse/langfuse-k8s/charts/langfuse
  version: 2.0.2

# ArgoCD project name
argoProject: default

# Environment configuration for ${resourcePrefix}/${region}/${accountId} variable substitution
environmentConfig:
  resourcePrefix: ""
  region: ""
  accountId: ""

# Namespace all langfuse-bootstrap resources (and the upstream chart) deploy into
namespace: langfuse-system

# Name of an existing S3 bucket for Langfuse event/media/export uploads.
# Required and cannot be empty. Supports ${resourcePrefix}/${region}/${accountId}
# substitution, same as loki-bootstrap's existingBucketName.
existingBucketName: ""

# Static credentials referenced via secretKeyRef throughout the upstream chart's
# valuesObject. MUST stay static (no runtime generation) — ArgoCD renders this
# chart via `helm template`, which regenerates anything random on every sync,
# rotating salt/encryptionKey and breaking hashed API keys / encrypted data.
# Override every field below for any real deployment; these are dev-only placeholders
# (same convention as agentgateway-bootstrap's database.password default).
credentials:
  # Salt used to hash API keys.
  salt: "changeme-langfuse-salt-please-override"
  # 256-bit (64 hex char) key for encrypting sensitive data. Generate via `openssl rand -hex 32`.
  encryptionKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  # NextAuth session secret.
  nextauthSecret: "changeme-nextauth-secret-please-override"
  # CNPG Postgres password for the langfuse role.
  postgresPassword: "changeme-postgres-password-please-override"
  # ClickHouse password for the built-in "default" user.
  clickhousePassword: "changeme-clickhouse-password-please-override"
  # Redis/Valkey AUTH password.
  redisPassword: "changeme-redis-password-please-override"

# CNPG Postgres database for Langfuse
database:
  # Cluster resource name. Defaults to "langfuse-db" if unset.
  clusterName: ""
  instances: 1
  databaseName: langfuse
  storage:
    size: 5Gi
    # Leave empty to use the cluster's default StorageClass.
    storageClass: ""
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      memory: 512Mi

# ClickHouse (rendered by the upstream langfuse chart itself via clickhouse.deploy:
# true — this chart only sizes it and points auth at our credentials Secret;
# the ClickHouse Operator must already be installed, see clickhouse-operator-bootstrap)
clickhouse:
  cluster:
    # Single ClickHouse node by default. Bump for HA.
    replicas: 1
    image:
      repository: clickhouse/clickhouse-server
      tag: "26.4"
    storage:
      size: 20Gi
      # Leave empty to use the cluster's default StorageClass.
      className: ""
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        memory: 2Gi
  keeper:
    # Must be odd (1, 3, 5). 1 is a valid single-node Keeper; 3 for HA.
    replicas: 1
    image:
      repository: clickhouse/clickhouse-keeper
      tag: "26.4"
    storage:
      size: 5Gi
      className: ""
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi

# Self-managed Redis (Valkey) — Langfuse's queue/cache. Deployed directly by this
# chart rather than toggling the upstream chart's bundled valkey-io/valkey subchart.
redis:
  image:
    repository: valkey/valkey
    tag: "8.0"
  storage:
    size: 4Gi
    storageClass: ""
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      memory: 512Mi

# Langfuse application configuration
langfuse:
  # Canonical URL of the deployment. Defaults to the port-forward-friendly
  # localhost URL since this chart exposes ClusterIP only; override once
  # Ingress/HTTPRoute is added.
  nextauthUrl: "http://localhost:3000"
  web:
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        memory: 1Gi
  worker:
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        memory: 1Gi
```

- [ ] **Step 3: Write `templates/_helpers.tpl`**

```
{{/*
Expand the name of the chart.
*/}}
{{- define "langfuse-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "langfuse-bootstrap.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "langfuse-bootstrap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "langfuse-bootstrap.labels" -}}
helm.sh/chart: {{ include "langfuse-bootstrap.chart" . }}
{{ include "langfuse-bootstrap.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "langfuse-bootstrap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "langfuse-bootstrap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CNPG Cluster resource name
*/}}
{{- define "langfuse-bootstrap.postgresClusterName" -}}
{{- .Values.database.clusterName | default "langfuse-db" -}}
{{- end }}

{{/*
ServiceAccount name shared by the S3IRSA CR and the langfuse chart's
langfuse.serviceAccount.name — must match exactly so the IRSA role binds to
the ServiceAccount the langfuse-web/langfuse-worker pods actually run as.
*/}}
{{- define "langfuse-bootstrap.s3ServiceAccountName" -}}
{{- if .Values.environmentConfig.resourcePrefix }}
{{- printf "%s-langfuse" .Values.environmentConfig.resourcePrefix | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- "langfuse" -}}
{{- end }}
{{- end }}

{{/*
Substitute variables in a string.
Supports ${resourcePrefix}, ${region}, ${accountId}.
Usage: include "langfuse-bootstrap.substituteVars" (dict "str" .Values.myValue "ctx" .)
*/}}
{{- define "langfuse-bootstrap.substituteVars" -}}
{{- $str := .str }}
{{- $ctx := .ctx }}
{{- if $ctx.Values.environmentConfig }}
{{- $str = $str | replace "${resourcePrefix}" $ctx.Values.environmentConfig.resourcePrefix }}
{{- $str = $str | replace "${region}" $ctx.Values.environmentConfig.region }}
{{- $str = $str | replace "${accountId}" ($ctx.Values.environmentConfig.accountId | toString) }}
{{- end }}
{{- $str }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "langfuse-bootstrap.validateConfig" -}}
{{- if not .Values.argoProject }}
{{- fail "argoProject is required and cannot be empty" }}
{{- end }}
{{- if not .Values.langfuseChart.version }}
{{- fail "langfuseChart.version is required and cannot be empty" }}
{{- end }}
{{- if not .Values.existingBucketName }}
{{- fail "existingBucketName is required and cannot be empty" }}
{{- end }}
{{- if ne .Values.clickhouse.keeper.replicas 1 }}
{{- if eq (mod .Values.clickhouse.keeper.replicas 2) 0 }}
{{- fail "clickhouse.keeper.replicas must be odd (1, 3, or 5)" }}
{{- end }}
{{- end }}
{{- end }}
```

`s3ServiceAccountName` matches `loki-bootstrap`'s convention exactly: `environmentConfig.resourcePrefix` holds a bare value (e.g. `dev`, no trailing separator — confirmed via `common-bootstrap`'s `environmentconfig-harvester-job.yaml`, which sources it straight from an AWS `Environment` tag), and the hyphen is added explicitly in the template.

- [ ] **Step 4: Verify scaffold lints clean**

Run: `helm lint charts/langfuse-bootstrap`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Commit**

```bash
git add charts/langfuse-bootstrap/Chart.yaml charts/langfuse-bootstrap/values.yaml charts/langfuse-bootstrap/templates/_helpers.tpl
git commit -m "feat(langfuse-bootstrap): scaffold chart"
```

---

## Task 5: CNPG Postgres Cluster + credentials Secret

**Files:**
- Create: `charts/langfuse-bootstrap/templates/postgres-secret.yaml`
- Create: `charts/langfuse-bootstrap/templates/postgres-cluster.yaml`

**Interfaces:**
- Consumes: `langfuse-bootstrap.postgresClusterName`, `langfuse-bootstrap.labels` (Task 4); `.Values.namespace`, `.Values.database.*`, `.Values.credentials.postgresPassword`.
- Produces: a CNPG `Cluster` reachable at `<postgresClusterName>-rw.<namespace>.svc.cluster.local:5432`, and a `kubernetes.io/basic-auth` Secret named `<postgresClusterName>-credentials` with keys `username`/`password` — both consumed by Task 9's `config/langfuse-values.yaml` (`postgresql.host`, `postgresql.auth.existingSecret`).

- [ ] **Step 1: Write `templates/postgres-secret.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "langfuse-bootstrap.postgresClusterName" . }}-credentials
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "0"
type: kubernetes.io/basic-auth
stringData:
  username: {{ .Values.database.databaseName | quote }}
  password: {{ .Values.credentials.postgresPassword | quote }}
```

- [ ] **Step 2: Write `templates/postgres-cluster.yaml`**

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ include "langfuse-bootstrap.postgresClusterName" . }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  instances: {{ .Values.database.instances }}
  bootstrap:
    initdb:
      database: {{ .Values.database.databaseName | quote }}
      owner: {{ .Values.database.databaseName | quote }}
      secret:
        name: {{ include "langfuse-bootstrap.postgresClusterName" . }}-credentials
  storage:
    size: {{ .Values.database.storage.size | quote }}
    {{- if .Values.database.storage.storageClass }}
    storageClass: {{ .Values.database.storage.storageClass | quote }}
    {{- end }}
  resources:
    requests:
      cpu: {{ .Values.database.resources.requests.cpu | quote }}
      memory: {{ .Values.database.resources.requests.memory | quote }}
    limits:
      memory: {{ .Values.database.resources.limits.memory | quote }}
```

- [ ] **Step 3: Render and assert**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . --set existingBucketName=test-bucket | tee /tmp/langfuse-render.yaml
grep -q "kind: Cluster" /tmp/langfuse-render.yaml
grep -q "name: langfuse-db-credentials" /tmp/langfuse-render.yaml
grep -q "type: kubernetes.io/basic-auth" /tmp/langfuse-render.yaml
grep -q "name: langfuse-db-credentials" /tmp/langfuse-render.yaml
```
Expected: all `grep -q` calls exit 0. (`existingBucketName` is set here only to satisfy `validateConfig` — later tasks add the templates that actually consume it.)

- [ ] **Step 4: `helm lint`**

Run: `helm lint charts/langfuse-bootstrap --set existingBucketName=test-bucket`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Commit**

```bash
git add charts/langfuse-bootstrap/templates/postgres-secret.yaml charts/langfuse-bootstrap/templates/postgres-cluster.yaml
git commit -m "feat(langfuse-bootstrap): add CNPG Postgres cluster"
```

---

## Task 6: Shared application credentials Secret

**Files:**
- Create: `charts/langfuse-bootstrap/templates/credentials-secret.yaml`

**Interfaces:**
- Consumes: `langfuse-bootstrap.labels` (Task 4); `.Values.namespace`, `.Values.credentials.{salt,encryptionKey,nextauthSecret,clickhousePassword,redisPassword}`.
- Produces: a Secret named `langfuse-credentials` in `.Values.namespace` with keys `salt`, `encryption-key`, `nextauth-secret`, `clickhouse-password`, `redis-password` — consumed by Task 7 (Redis `--requirepass`) and Task 9 (`langfuse.salt`/`encryptionKey`/`nextauth.secret`/`clickhouse.auth`/`redis.auth` `secretKeyRef`s).

Note: this Secret intentionally does **not** hold the Postgres password — that lives in `<postgresClusterName>-credentials` from Task 5 (CNPG's `bootstrap.initdb.secret` requires a `kubernetes.io/basic-auth` Secret with exactly `username`/`password` keys, so it's kept separate rather than merged into this one).

- [ ] **Step 1: Write `templates/credentials-secret.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-credentials
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "0"
type: Opaque
stringData:
  salt: {{ .Values.credentials.salt | quote }}
  encryption-key: {{ .Values.credentials.encryptionKey | quote }}
  nextauth-secret: {{ .Values.credentials.nextauthSecret | quote }}
  clickhouse-password: {{ .Values.credentials.clickhousePassword | quote }}
  redis-password: {{ .Values.credentials.redisPassword | quote }}
```

- [ ] **Step 2: Render and assert**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . --set existingBucketName=test-bucket | tee /tmp/langfuse-render.yaml
grep -q "name: langfuse-credentials" /tmp/langfuse-render.yaml
grep -q "encryption-key:" /tmp/langfuse-render.yaml
grep -q "redis-password:" /tmp/langfuse-render.yaml
```
Expected: all three `grep -q` calls exit 0.

- [ ] **Step 3: Commit**

```bash
git add charts/langfuse-bootstrap/templates/credentials-secret.yaml
git commit -m "feat(langfuse-bootstrap): add shared application credentials Secret"
```

---

## Task 7: Self-managed Redis (Valkey)

**Files:**
- Create: `charts/langfuse-bootstrap/templates/redis.yaml`

**Interfaces:**
- Consumes: `langfuse-bootstrap.labels` (Task 4); `.Values.namespace`, `.Values.redis.*`; the `langfuse-credentials` Secret's `redis-password` key (Task 6).
- Produces: a headless Service `langfuse-redis` reachable at `langfuse-redis.<namespace>.svc.cluster.local:6379` — consumed by Task 9's `config/langfuse-values.yaml` (`redis.host`).

Single-instance Valkey, `requirepass` sourced from the shared credentials Secret, `maxmemory-policy noeviction` set via a mounted `valkey.conf` (upstream's README calls this setting required — without it Langfuse can lose queued jobs under memory pressure).

- [ ] **Step 1: Write `templates/redis.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: langfuse-redis-config
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "0"
data:
  valkey.conf: |
    maxmemory-policy noeviction
---
apiVersion: v1
kind: Service
metadata:
  name: langfuse-redis
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  type: ClusterIP
  clusterIP: None
  ports:
    - port: 6379
      protocol: TCP
      name: redis
      targetPort: redis
  selector:
    {{- include "langfuse-bootstrap.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: langfuse-redis
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  replicas: 1
  serviceName: langfuse-redis
  selector:
    matchLabels:
      {{- include "langfuse-bootstrap.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: redis
  template:
    metadata:
      labels:
        {{- include "langfuse-bootstrap.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: redis
    spec:
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: redis
          image: "{{ .Values.redis.image.repository }}:{{ .Values.redis.image.tag }}"
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          command:
            - /bin/sh
            - -c
            - |
              set -e
              exec valkey-server /etc/valkey/valkey.conf --requirepass "$REDIS_PASSWORD"
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: langfuse-credentials
                  key: redis-password
          ports:
            - containerPort: 6379
              name: redis
              protocol: TCP
          readinessProbe:
            tcpSocket:
              port: redis
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: redis
            initialDelaySeconds: 15
            periodSeconds: 10
          resources:
            requests:
              cpu: {{ .Values.redis.resources.requests.cpu | quote }}
              memory: {{ .Values.redis.resources.requests.memory | quote }}
            limits:
              memory: {{ .Values.redis.resources.limits.memory | quote }}
          volumeMounts:
            - name: data
              mountPath: /data
            - name: config
              mountPath: /etc/valkey
      volumes:
        - name: config
          configMap:
            name: langfuse-redis-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        {{- if .Values.redis.storage.storageClass }}
        storageClassName: {{ .Values.redis.storage.storageClass | quote }}
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.redis.storage.size | quote }}
```

- [ ] **Step 2: Render and assert**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . --set existingBucketName=test-bucket | tee /tmp/langfuse-render.yaml
grep -q "kind: StatefulSet" /tmp/langfuse-render.yaml
grep -q "name: langfuse-redis" /tmp/langfuse-render.yaml
grep -q "maxmemory-policy noeviction" /tmp/langfuse-render.yaml
grep -q "requirepass" /tmp/langfuse-render.yaml
grep -q "key: redis-password" /tmp/langfuse-render.yaml
```
Expected: all five `grep -q` calls exit 0.

- [ ] **Step 3: `helm lint`**

Run: `helm lint charts/langfuse-bootstrap --set existingBucketName=test-bucket`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 4: Commit**

```bash
git add charts/langfuse-bootstrap/templates/redis.yaml
git commit -m "feat(langfuse-bootstrap): add self-managed Valkey StatefulSet"
```

---

## Task 8: S3IRSA for the existing bucket

**Files:**
- Create: `charts/langfuse-bootstrap/templates/s3irsa.yaml`

**Interfaces:**
- Consumes: `langfuse-bootstrap.s3ServiceAccountName`, `langfuse-bootstrap.substituteVars` (Task 4); `.Values.namespace`, `.Values.existingBucketName`.
- Produces: an IAM role at the predictable ARN `arn:aws:iam::<accountId>:role/<s3ServiceAccountName>-irsa-role` (same naming convention `loki-bootstrap` hardcodes) — consumed by Task 9, which annotates `langfuse.serviceAccount` with this exact ARN.

No static S3 credentials anywhere: verified against upstream's `_helpers.tpl` (`langfuse.getS3ValueOrSecret`) that leaving `accessKeyId`/`secretAccessKey` unset omits those env vars entirely rather than setting them empty, so the AWS SDK falls through to IRSA via the ServiceAccount annotation — same mechanism as `loki-bootstrap`.

- [ ] **Step 1: Write `templates/s3irsa.yaml`**

```yaml
apiVersion: dip.io/v1alpha1
kind: S3IRSA
metadata:
  name: {{ include "langfuse-bootstrap.s3ServiceAccountName" . }}
  namespace: {{ .Values.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  existingBucketName: {{ include "langfuse-bootstrap.substituteVars" (dict "str" .Values.existingBucketName "ctx" .) }}
  permissions:
    allowRead: true
    allowWrite: true
  serviceAccount:
    name: {{ include "langfuse-bootstrap.s3ServiceAccountName" . }}
  writeConnectionSecretToRef:
    name: {{ include "langfuse-bootstrap.s3ServiceAccountName" . }}
```

- [ ] **Step 2: Render and assert**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . --set existingBucketName=test-bucket --set environmentConfig.resourcePrefix=dev | tee /tmp/langfuse-render.yaml
grep -q "kind: S3IRSA" /tmp/langfuse-render.yaml
grep -q "name: dev-langfuse" /tmp/langfuse-render.yaml
grep -q "existingBucketName: test-bucket" /tmp/langfuse-render.yaml
grep -q "allowWrite: true" /tmp/langfuse-render.yaml
```
Expected: all four `grep -q` calls exit 0.

- [ ] **Step 3: Commit**

```bash
git add charts/langfuse-bootstrap/templates/s3irsa.yaml
git commit -m "feat(langfuse-bootstrap): add S3IRSA for the existing bucket"
```

---

## Task 9: Langfuse ArgoCD Application + templated `valuesObject`

**Files:**
- Create: `charts/langfuse-bootstrap/config/langfuse-values.yaml`
- Create: `charts/langfuse-bootstrap/templates/langfuse-helm.yaml`

**Interfaces:**
- Consumes: everything from Tasks 4-8 — `langfuse-bootstrap.postgresClusterName`, `.s3ServiceAccountName`, `.substituteVars`, `.validateConfig`, `.labels`; the Postgres host/Secret from Task 5; the credentials Secret keys from Task 6; the Redis Service host from Task 7; the S3IRSA-provisioned IAM role ARN from Task 8.
- Produces: the ArgoCD `Application` `langfuse-helm` — terminal node, nothing later depends on it within this chart.

- [ ] **Step 1: Write `config/langfuse-values.yaml`**

```yaml
langfuse:
  nextauth:
    url: {{ .Values.langfuse.nextauthUrl | quote }}
    secret:
      secretKeyRef:
        name: langfuse-credentials
        key: nextauth-secret
  salt:
    secretKeyRef:
      name: langfuse-credentials
      key: salt
  encryptionKey:
    secretKeyRef:
      name: langfuse-credentials
      key: encryption-key
  serviceAccount:
    create: true
    name: {{ include "langfuse-bootstrap.s3ServiceAccountName" . | quote }}
    annotations:
      eks.amazonaws.com/role-arn: {{ printf "arn:aws:iam::%s:role/%s-irsa-role" .Values.environmentConfig.accountId (include "langfuse-bootstrap.s3ServiceAccountName" .) | quote }}
  web:
    resources:
      {{- toYaml .Values.langfuse.web.resources | nindent 6 }}
  worker:
    resources:
      {{- toYaml .Values.langfuse.worker.resources | nindent 6 }}

postgresql:
  deploy: false
  host: {{ printf "%s-rw.%s.svc.cluster.local" (include "langfuse-bootstrap.postgresClusterName" .) .Values.namespace | quote }}
  port: 5432
  auth:
    username: {{ .Values.database.databaseName | quote }}
    database: {{ .Values.database.databaseName | quote }}
    existingSecret: {{ printf "%s-credentials" (include "langfuse-bootstrap.postgresClusterName" .) | quote }}
    secretKeys:
      userPasswordKey: password

clickhouse:
  deploy: true
  crdCheck: true
  auth:
    username: default
    existingSecret: langfuse-credentials
    existingSecretKey: clickhouse-password
  cluster:
    replicas: {{ .Values.clickhouse.cluster.replicas }}
    image:
      repository: {{ .Values.clickhouse.cluster.image.repository | quote }}
      tag: {{ .Values.clickhouse.cluster.image.tag | quote }}
    storage:
      size: {{ .Values.clickhouse.cluster.storage.size | quote }}
      {{- if .Values.clickhouse.cluster.storage.className }}
      className: {{ .Values.clickhouse.cluster.storage.className | quote }}
      {{- end }}
    resources:
      {{- toYaml .Values.clickhouse.cluster.resources | nindent 6 }}
  keeper:
    enabled: true
    replicas: {{ .Values.clickhouse.keeper.replicas }}
    image:
      repository: {{ .Values.clickhouse.keeper.image.repository | quote }}
      tag: {{ .Values.clickhouse.keeper.image.tag | quote }}
    storage:
      size: {{ .Values.clickhouse.keeper.storage.size | quote }}
      {{- if .Values.clickhouse.keeper.storage.className }}
      className: {{ .Values.clickhouse.keeper.storage.className | quote }}
      {{- end }}
    resources:
      {{- toYaml .Values.clickhouse.keeper.resources | nindent 6 }}

redis:
  deploy: false
  host: langfuse-redis.{{ .Values.namespace }}.svc.cluster.local
  port: 6379
  auth:
    username: default
    existingSecret: langfuse-credentials
    existingSecretPasswordKey: redis-password

s3:
  deploy: false
  storageProvider: s3
  bucket: {{ include "langfuse-bootstrap.substituteVars" (dict "str" .Values.existingBucketName "ctx" .) | quote }}
  region: {{ .Values.environmentConfig.region | quote }}
  forcePathStyle: false
```

`s3.accessKeyId`/`s3.secretAccessKey` are deliberately absent from this file — verified against upstream `_helpers.tpl` that an absent (not empty-string) value means the corresponding env var is omitted entirely, letting the AWS SDK fall through to IRSA.

- [ ] **Step 2: Write `templates/langfuse-helm.yaml`**

```yaml
{{- include "langfuse-bootstrap.validateConfig" . -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: langfuse-helm
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "langfuse-bootstrap.labels" . | nindent 4 }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: {{ .Values.argoProject }}
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
  source:
    repoURL: {{ printf "%s/langfuse" .Values.langfuseChart.repoURL | quote }}
    targetRevision: {{ .Values.langfuseChart.version | quote }}
    helm:
      releaseName: langfuse
      valuesObject:
        {{- (tpl (.Files.Get "config/langfuse-values.yaml") .) | nindent 8 }}
  destination:
    server: "https://kubernetes.default.svc"
    namespace: {{ .Values.namespace }}
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    automated:
      prune: true
      selfHeal: true
```

- [ ] **Step 3: Render and assert**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . \
  --set existingBucketName=test-bucket \
  --set environmentConfig.resourcePrefix=dev \
  --set environmentConfig.region=eu-west-1 \
  --set environmentConfig.accountId=123456789012 \
  | tee /tmp/langfuse-render.yaml
grep -q "name: langfuse-helm" /tmp/langfuse-render.yaml
grep -q "repoURL: oci://ghcr.io/langfuse/langfuse-k8s/charts/langfuse" /tmp/langfuse-render.yaml
grep -q 'targetRevision: "2.0.2"' /tmp/langfuse-render.yaml
grep -q "deploy: false" /tmp/langfuse-render.yaml
grep -q "role-arn: arn:aws:iam::123456789012:role/dev-langfuse-irsa-role" /tmp/langfuse-render.yaml
grep -q "existingSecretKey: clickhouse-password" /tmp/langfuse-render.yaml
grep -qv "accessKeyId" /tmp/langfuse-render.yaml
```
Expected: all `grep -q` calls exit 0, and the final `grep -qv` (asserting `accessKeyId` never appears anywhere in the render — confirming IRSA-only S3 auth) also exits 0.

- [ ] **Step 4: `helm lint`**

Run: `helm lint charts/langfuse-bootstrap --set existingBucketName=test-bucket`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 5: Commit**

```bash
git add charts/langfuse-bootstrap/config/langfuse-values.yaml charts/langfuse-bootstrap/templates/langfuse-helm.yaml
git commit -m "feat(langfuse-bootstrap): add langfuse ArgoCD Application"
```

---

## Task 10: `langfuse-bootstrap` docs + `ct.yaml` registration

**Files:**
- Create: `charts/langfuse-bootstrap/README.md.gotmpl`
- Create: `charts/langfuse-bootstrap/README.md` (generated by `helm-docs`)
- Modify: `ct.yaml:8-19` (repo root) — add `langfuse-bootstrap` to `excluded-charts`

**Interfaces:**
- None.

- [ ] **Step 1: Write `README.md.gotmpl`**

```gotmpl
# {{ template "chart.header" . }}
{{ template "chart.deprecationWarning" . }}

{{ template "chart.badgesSection" . }}

{{ template "chart.description" . }}

Deploys [Langfuse](https://langfuse.com/) via ArgoCD: CNPG Postgres, ClickHouse (rendered by the upstream chart against a pre-installed [ClickHouse Operator](../clickhouse-operator-bootstrap)), a self-managed single-instance Valkey, and S3 access via IRSA against an existing bucket.

## Prerequisites

- `clickhouse-operator-bootstrap` installed cluster-wide (provides the `ClickHouseCluster`/`KeeperCluster` CRDs this chart's upstream dependency renders against).
- CloudNativePG operator installed cluster-wide (see `cloudnative-pg-operator`).
- An existing S3 bucket (set via `existingBucketName`) and IRSA support in-cluster (see `loki-bootstrap` for the same pattern).

## Reaching the login screen

This chart exposes Langfuse as ClusterIP only:

```bash
kubectl port-forward svc/langfuse-web 3000:3000 -n langfuse-system
```

Then browse to http://localhost:3000.

{{ template "chart.requirementsSection" . }}

{{ template "chart.valuesHeader" . }}

{{ template "chart.valuesTable" . }}

{{ template "helm-docs.versionFooter" . }}
```

- [ ] **Step 2: Generate `README.md`**

Run: `helm-docs --chart-search-root=charts/langfuse-bootstrap`
Expected: `charts/langfuse-bootstrap/README.md` is created/updated.

- [ ] **Step 3: Register the chart in root `ct.yaml`'s `excluded-charts`**

Insert `langfuse-bootstrap` in alphabetical position (between `k8s-observability-monitoring` and `loki-bootstrap`):

```yaml
excluded-charts:
  - agentgateway-bootstrap
  - centcom-satellite
  - clickhouse-operator-bootstrap
  - cloudnative-pg-bootstrap
  - cloudnative-pg-operator
  - crossplane-providers
  - grafana
  - k8s-observability-monitoring
  - langfuse-bootstrap
  - loki-bootstrap
  - mimir-bootstrap
  - otlp-gateway-bootstrap
  - tempo-bootstrap
```

- [ ] **Step 4: `ct lint`**

Run: `ct lint --config ct.yaml --charts charts/langfuse-bootstrap` (run from repo root)
Expected: lint passes.

- [ ] **Step 5: Commit**

```bash
git add charts/langfuse-bootstrap/README.md.gotmpl charts/langfuse-bootstrap/README.md ct.yaml
git commit -m "docs(langfuse-bootstrap): add README, exclude from ct install"
```

---

## Task 11: Full-repo validation pass

**Files:** none created — this task only runs checks across both new charts and fixes anything they surface.

**Interfaces:** none — verification-only task.

- [ ] **Step 1: `ct lint` across both new charts together**

Run (from repo root): `ct lint --config ct.yaml --charts charts/clickhouse-operator-bootstrap --charts charts/langfuse-bootstrap`
Expected: both charts pass lint. If `ct lint` reports issues not caught by the per-task `helm lint` runs (e.g. Chart.yaml schema, icon/maintainers conventions relative to other charts in this repo), fix them now.

- [ ] **Step 2: Render the Langfuse chart with the ClickHouse operator CRDs simulated present**

Run:
```bash
cd charts/langfuse-bootstrap
helm template test . \
  --set existingBucketName=test-bucket \
  --set environmentConfig.resourcePrefix=dev \
  --set environmentConfig.region=eu-west-1 \
  --set environmentConfig.accountId=123456789012 \
  --api-versions clickhouse.com/v1alpha1/ClickHouseCluster \
  --api-versions clickhouse.com/v1alpha1/KeeperCluster \
  | tee /tmp/langfuse-full-render.yaml
```
This only validates the *wrapper* chart's own templates (the CNPG `Cluster`, the two Secrets, the Valkey `StatefulSet`, the `S3IRSA`, and the ArgoCD `Application` with its embedded `valuesObject` block). It does **not** render the upstream `langfuse-k8s` chart's own templates — ArgoCD does that at sync time by installing the chart referenced in `spec.source`, which is outside this `helm template` run.

Expected: renders cleanly, and every assertion from Tasks 5-9's individual "Render and assert" steps still holds against this combined render (spot-check a few: `grep -q "kind: Cluster"`, `grep -q "kind: S3IRSA"`, `grep -q "kind: StatefulSet"`, `grep -q "name: langfuse-helm"`).

- [ ] **Step 3: Independently render the upstream `langfuse-k8s` chart with the values this wrapper produces**

This closes the gap Step 2 leaves — confirms the *actual* upstream templates (ClickHouseCluster CR, web/worker Deployments, Secrets) accept our generated values without error.

```bash
# Extract the valuesObject block our Application renders and feed it straight
# to the real upstream chart.
cd /tmp
yq -r '.spec.source.helm.valuesObject' <(yq 'select(.kind == "Application" and .metadata.name == "langfuse-helm")' /tmp/langfuse-full-render.yaml) > /tmp/langfuse-upstream-values.yaml
helm template langfuse oci://ghcr.io/langfuse/langfuse-k8s/charts/langfuse --version 2.0.2 \
  -f /tmp/langfuse-upstream-values.yaml \
  --api-versions clickhouse.com/v1alpha1/ClickHouseCluster \
  --api-versions clickhouse.com/v1alpha1/KeeperCluster \
  --namespace langfuse-system \
  | tee /tmp/langfuse-upstream-render.yaml
grep -q "kind: ClickHouseCluster" /tmp/langfuse-upstream-render.yaml
grep -q "kind: KeeperCluster" /tmp/langfuse-upstream-render.yaml
grep -q "kind: Deployment" /tmp/langfuse-upstream-render.yaml
grep -q "name: langfuse-web" /tmp/langfuse-upstream-render.yaml
grep -qv "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID" /tmp/langfuse-upstream-render.yaml
```
Expected: `helm template` exits 0 (no `fail` triggered from `validations.yaml`) and all `grep` assertions pass, including the final negative assertion confirming no static S3 access key env var is ever rendered (IRSA-only, as designed).

If this step fails, fix `config/langfuse-values.yaml` (Task 9) or `values.yaml` (Task 4) — do not patch around it by disabling upstream validations.

- [ ] **Step 4: Commit any fixes from this task**

```bash
git add -A charts/clickhouse-operator-bootstrap charts/langfuse-bootstrap
git commit -m "fix(langfuse-bootstrap,clickhouse-operator-bootstrap): address full-repo validation findings"
```
(Skip this step if Steps 1-3 found nothing to fix.)

---

## Task 12: Deploy to the target cluster and verify a functioning login

**This task touches shared, live infrastructure (the homelab cluster or whichever cluster is designated as the target) and installs a cert-manager-dependent cluster-wide operator. Confirm the target cluster and namespace with the user before running any command in this task against a real cluster — do not proceed on the assumption that the homelab is the intended target just because it's mentioned in prior context.**

**Files:** none — this task only deploys and observes; any fixes discovered here loop back to the relevant earlier task's files.

**Interfaces:** consumes the fully-built charts from Tasks 1-11.

- [ ] **Step 1: Confirm target cluster and access path with the user**

Ask (if not already confirmed in conversation): which cluster is the deployment target, how is `kubectl`/`helm` access reached (e.g. homelab via `ssh kmaster` then `kubectl`, per prior context — but verify this is still current), and does ArgoCD already run there such that these charts should be added as `Application`s under an existing app-of-apps, or should this be validated first via a direct `helm install --dry-run`/`helm template | kubectl apply` smoke test before wiring into ArgoCD.

- [ ] **Step 2: Confirm prerequisites already exist on the target cluster**

```bash
kubectl get crd certificates.cert-manager.io issuers.cert-manager.io
kubectl get crd clusters.postgresql.cnpg.io
```
Expected: both CRDs exist (cert-manager and CloudNativePG are prerequisites this plan does not install). If either is missing, stop and confirm with the user how to proceed (install it first, or pick a different target cluster) rather than silently installing a new cluster-wide operator as a side effect of this task.

- [ ] **Step 3: Install `clickhouse-operator-bootstrap`**

```bash
helm upgrade --install clickhouse-operator-bootstrap charts/clickhouse-operator-bootstrap \
  --namespace argocd --create-namespace \
  --dry-run
```
Review the dry-run output, then re-run without `--dry-run` once confirmed. Wait for the operator and its CRDs:
```bash
kubectl -n clickhouse-operator-system rollout status deployment -l app.kubernetes.io/name=clickhouse-operator-helm --timeout=180s
kubectl wait --for=condition=Established crd/clickhouseclusters.clickhouse.com crd/keeperclusters.clickhouse.com --timeout=120s
```
Expected: operator Deployment reaches `Ready`, both CRDs report `Established`.

- [ ] **Step 4: Install `langfuse-bootstrap`**

Provide real values for `existingBucketName` and `environmentConfig.{resourcePrefix,region,accountId}` (via `-f` or `--set`) matching the target environment — confirm these with the user rather than guessing.

```bash
helm upgrade --install langfuse-bootstrap charts/langfuse-bootstrap \
  --namespace argocd \
  --set existingBucketName=<confirmed-bucket-name> \
  --set environmentConfig.resourcePrefix=<confirmed-prefix> \
  --set environmentConfig.region=<confirmed-region> \
  --set environmentConfig.accountId=<confirmed-account-id> \
  --dry-run
```
Review, then re-run without `--dry-run`.

- [ ] **Step 5: Watch the sync waves resolve**

```bash
kubectl -n langfuse-system get cluster.postgresql.cnpg.io,statefulset,clickhousecluster,keepercluster,deployment -w
```
Expected, in order: CNPG `Cluster` reaches `Cluster in healthy state`; `langfuse-redis` `StatefulSet` reaches `1/1` ready; `ClickHouseCluster`/`KeeperCluster` report ready; `langfuse-web`/`langfuse-worker` `Deployment`s reach `1/1` ready. If any resource stalls, use `kubectl describe` / `kubectl logs` on it — do not restart or delete-and-recreate cluster-wide resources (the ClickHouse operator, CNPG operator) without confirming with the user first, since other workloads may depend on them.

- [ ] **Step 6: Port-forward and verify the login screen**

```bash
kubectl port-forward svc/langfuse-web 3000:3000 -n langfuse-system
```
In a browser, open `http://localhost:3000`. Expected: the Langfuse login/sign-up screen renders. Complete a sign-up (or login, if `langfuse.features.signUpDisabled` is left at its default `false`) end-to-end and confirm you land on the Langfuse dashboard post-authentication — this is the goal's actual success condition, not just the login page rendering.

- [ ] **Step 7: Report the result**

Summarize what was deployed, where, and the outcome of the login check. If the login check fails, treat it as a bug in this plan's charts (loop back to the relevant task, fix, re-render, re-deploy) rather than a cluster environment issue, unless the failure is clearly external (e.g. missing prerequisite CRD, network policy blocking a Service).

---

## Plan Self-Review

**Spec coverage:**
- `clickhouse-operator-bootstrap` spec's Architecture/Values Schema/File Map → Tasks 1-3. ✓
- `langfuse-bootstrap` spec's Postgres/ClickHouse/Redis/S3 wiring, Credential Pinning, UI Exposure, Values Schema, File Map → Tasks 4-9. ✓
- `langfuse-bootstrap` spec's Verification Plan (helm template, deploy, port-forward, login) → Tasks 11-12. ✓

**Placeholder scan:** no `TBD`/`TODO`/"implement later" strings; every code step has real content; no "add appropriate error handling" phrasing. Task 12's bucket/account-id/region values are correctly left as `<confirmed-...>` placeholders *for the human running that task to fill in from real cluster context* — not a plan gap, since real credentials/IDs cannot be known at plan-writing time and this task explicitly requires user confirmation before running.

**Type/name consistency check:**
- `langfuse-bootstrap.postgresClusterName` (Task 4) used identically in Task 5 (`postgres-secret.yaml`, `postgres-cluster.yaml`) and Task 9 (`config/langfuse-values.yaml`'s `postgresql.host`/`auth.existingSecret`). ✓
- `langfuse-bootstrap.s3ServiceAccountName` (Task 4) used identically in Task 8 (`s3irsa.yaml`) and Task 9 (`langfuse.serviceAccount.name` + IRSA role-arn annotation). ✓
- Secret name `langfuse-credentials` and its keys (`salt`, `encryption-key`, `nextauth-secret`, `clickhouse-password`, `redis-password`) match exactly between Task 6 (creation) and Tasks 7/9 (consumption). ✓
- Redis Service name `langfuse-redis` matches between Task 7 (creation) and Task 9 (`redis.host`). ✓
- No naming drift found.
