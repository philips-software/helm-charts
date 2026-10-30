# Barman Cloud Plugin Helm Chart Integration - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add barman-cloud plugin deployment to the cloudnative-pg-operator helm chart via an ArgoCD Application.

**Architecture:** Create a new ArgoCD Application template that deploys the official `cloudnative-pg/plugin-barman-cloud` helm chart (v0.6.0) to the same namespace as the CNPG operator, using sync-wave ordering to ensure it deploys after the operator.

**Tech Stack:** Helm, ArgoCD, Kubernetes

**Chart Path:** `/Users/andy/DEV/Philips/philips-software/helm-charts/charts/cloudnative-pg-operator`

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `values.yaml` | Modify | Add `barmanCloudPlugin` configuration section |
| `templates/barman-cloud-plugin.yaml` | Create | ArgoCD Application for plugin deployment |
| `Chart.yaml` | Modify | Bump chart version |
| `README.md` | Modify | Document new configuration option |

---

### Task 1: Add Plugin Configuration to values.yaml

**Files:**
- Modify: `values.yaml`

- [ ] **Step 1: Add barmanCloudPlugin section to values.yaml**

Add at the end of the file:

```yaml
barmanCloudPlugin:
  enabled: true
  # renovate: datasource=helm depName=plugin-barman-cloud registryUrl=https://cloudnative-pg.io/charts
  version: 0.6.0
```

- [ ] **Step 2: Verify helm template renders**

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/cloudnative-pg-operator
helm template test . --set environmentConfig.resourcePrefix=test --set environmentConfig.sharedServicesAccountId=123456789012 --set environmentConfig.region=us-east-1 2>&1 | head -20
```

Expected: No errors, existing templates render.

- [ ] **Step 3: Commit**

```bash
git add values.yaml
git commit -m "feat(cloudnative-pg-operator): add barmanCloudPlugin configuration"
```

---

### Task 2: Create ArgoCD Application Template

**Files:**
- Create: `templates/barman-cloud-plugin.yaml`

- [ ] **Step 1: Create the barman-cloud-plugin.yaml template**

```yaml
{{- if .Values.barmanCloudPlugin.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: plugin-barman-cloud
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "cloudnative-pg-operator.labels" . | nindent 4 }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: {{ .Values.argoProject }}
  source:
    chart: plugin-barman-cloud
    repoURL: https://cloudnative-pg.io/charts/
    targetRevision: {{ .Values.barmanCloudPlugin.version }}
    helm:
      releaseName: plugin-barman-cloud
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
{{- end }}
```

- [ ] **Step 2: Verify template renders correctly**

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/cloudnative-pg-operator
helm template test . --set environmentConfig.resourcePrefix=test --set environmentConfig.sharedServicesAccountId=123456789012 --set environmentConfig.region=us-east-1 | grep -A 50 "name: plugin-barman-cloud"
```

Expected: Shows the rendered ArgoCD Application with correct values.

- [ ] **Step 3: Verify template is not rendered when disabled**

```bash
helm template test . --set environmentConfig.resourcePrefix=test --set environmentConfig.sharedServicesAccountId=123456789012 --set environmentConfig.region=us-east-1 --set barmanCloudPlugin.enabled=false | grep "plugin-barman-cloud" || echo "Not found (correct)"
```

Expected: "Not found (correct)"

- [ ] **Step 4: Commit**

```bash
git add templates/barman-cloud-plugin.yaml
git commit -m "feat(cloudnative-pg-operator): add barman-cloud plugin ArgoCD Application"
```

---

### Task 3: Bump Chart Version

**Files:**
- Modify: `Chart.yaml`

- [ ] **Step 1: Update chart version**

Change version from `0.6.3` to `0.7.0`:

```yaml
apiVersion: v2
name: cloudnative-pg-operator
version: 0.7.0
description: A Helm chart for bootstrapping CloudNativePG operator with Kyverno policies
```

- [ ] **Step 2: Commit**

```bash
git add Chart.yaml
git commit -m "chore(cloudnative-pg-operator): bump version to 0.7.0"
```

---

### Task 4: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add documentation for barmanCloudPlugin**

Add a new section to the README documenting the new configuration:

```markdown
## Barman Cloud Plugin

The chart can optionally deploy the [barman-cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/) for CloudNativePG. This plugin provides the new backup architecture that will replace the deprecated native barman support in CNPG 1.30.

### Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `barmanCloudPlugin.enabled` | Enable barman-cloud plugin deployment | `true` |
| `barmanCloudPlugin.version` | Helm chart version to deploy | `0.6.0` |

The plugin is deployed as an ArgoCD Application with sync-wave `1`, ensuring it deploys after the CNPG operator (sync-wave `0`).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(cloudnative-pg-operator): document barmanCloudPlugin configuration"
```

---

### Task 5: Run helm-docs

**Files:**
- Regenerates: `README.md` (if helm-docs is configured)

- [ ] **Step 1: Run helm-docs if available**

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/cloudnative-pg-operator
helm-docs 2>/dev/null || echo "helm-docs not configured for this chart"
```

- [ ] **Step 2: Commit any changes**

```bash
git diff README.md && git add README.md && git commit -m "docs(cloudnative-pg-operator): regenerate docs" || echo "No changes from helm-docs"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Run full helm template**

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/cloudnative-pg-operator
helm template test . --set environmentConfig.resourcePrefix=test --set environmentConfig.sharedServicesAccountId=123456789012 --set environmentConfig.region=us-east-1
```

Expected: All templates render without errors.

- [ ] **Step 2: Verify sync-wave ordering**

```bash
helm template test . --set environmentConfig.resourcePrefix=test --set environmentConfig.sharedServicesAccountId=123456789012 --set environmentConfig.region=us-east-1 | grep -B 5 "sync-wave"
```

Expected: Shows `sync-wave: "0"` for cloudnative-pg and `sync-wave: "1"` for plugin-barman-cloud.

- [ ] **Step 3: Lint the chart**

```bash
helm lint .
```

Expected: No errors.

---

## Rollback

If issues occur after deployment:

```bash
# Disable the plugin
helm upgrade <release> . --set barmanCloudPlugin.enabled=false
```

Or revert to previous chart version.
