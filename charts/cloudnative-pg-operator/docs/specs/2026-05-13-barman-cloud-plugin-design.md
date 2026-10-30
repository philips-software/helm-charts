# Barman Cloud Plugin Helm Chart Integration

**Date:** 2026-05-13  
**Status:** Approved

## Summary

Add the barman-cloud plugin deployment to the cloudnative-pg-operator helm chart using the official upstream helm chart via an ArgoCD Application.

## Background

CloudNativePG is deprecating native barman backup support (removed in v1.30). The new plugin-based architecture requires installing the barman-cloud plugin separately.

## Design

### Approach

Deploy the official `cloudnative-pg/plugin-barman-cloud` helm chart (v0.6.0) via an ArgoCD Application, following the same pattern as the existing CNPG operator deployment.

### File Changes

**1. Modify `values.yaml`**

Add plugin configuration section:

```yaml
barmanCloudPlugin:
  enabled: true
  # renovate: datasource=helm depName=plugin-barman-cloud registryUrl=https://cloudnative-pg.io/charts
  version: 0.6.0
```

**2. Create `templates/barman-cloud-plugin.yaml`**

New ArgoCD Application:

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

**3. Update `Chart.yaml`**

Bump chart version.

### Sync Wave Ordering

- CNPG operator: `sync-wave: "0"`
- Barman cloud plugin: `sync-wave: "1"`

Plugin deploys after operator is ready.

### Image Handling

No ECR mirroring needed - handled automatically via ECR pull-through cache and Kyverno mutating webhook.

### Prerequisites

- cert-manager must be installed (already deployed)
- CNPG operator must be running (enforced via sync-wave)

## Testing

1. Deploy to test cluster
2. Verify plugin pod running in cnpg-system namespace
3. Verify ObjectStore CRD is available
4. Create test ObjectStore resource

## Future Work

After plugin is deployed, the Crossplane postgres-cnpg composition needs to be updated to use the plugin instead of native barman support. This is tracked in the migration plan at `docs/barman-cloud-plugin-migration-plan.md`.
