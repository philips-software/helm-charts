# Agentgateway 1.4.1 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `agentgateway-bootstrap` Helm chart to support upstream `agentgateway` version `1.4.1`.

**Architecture:** Update chart metadata, default values for sub-charts (`agentgateway-crds` and `agentgateway`), and user documentation to reference version `1.4.1` and bump the bootstrap chart version to `0.5.0`.

**Tech Stack:** Helm, Kubernetes, YAML, Markdown

## Global Constraints
- Target `agentgateway` upstream chart versions: `1.4.1`
- Chart version: `0.5.0`
- AppVersion: `"1.4.1"`

---

### Task 1: Update Chart Metadata and Sub-chart Version Defaults

**Files:**
- Modify: `charts/agentgateway-bootstrap/Chart.yaml:5-6`
- Modify: `charts/agentgateway-bootstrap/values.yaml:7,13`

**Interfaces:**
- Consumes: None
- Produces: Updated `Chart.yaml` and `values.yaml` with version `0.5.0` and app version `1.4.1`.

- [ ] **Step 1: Update `Chart.yaml`**

Update `version` to `0.5.0` and `appVersion` to `"1.4.1"` in `Chart.yaml`.

```yaml
version: 0.5.0
appVersion: "1.4.1"
```

- [ ] **Step 2: Update `values.yaml`**

Update `agentgatewayCrdsChart.version` and `agentgatewayChart.version` in `values.yaml` to `1.4.1`.

```yaml
agentgatewayCrdsChart:
  repoURL: oci://cr.agentgateway.dev/charts
  # renovate: datasource=docker depName=cr.agentgateway.dev/charts/agentgateway-crds
  version: 1.4.1

agentgatewayChart:
  repoURL: oci://cr.agentgateway.dev/charts
  # renovate: datasource=docker depName=cr.agentgateway.dev/charts/agentgateway
  version: 1.4.1
```

- [ ] **Step 3: Verify chart syntax and template rendering**

Run: `helm lint .` and `helm template test .`
Expected: `1 Chart(s) linted, 0 chart(s) failed` and manifests rendered with `agentgateway-bootstrap-0.5.0` and `app.kubernetes.io/version: "1.4.1"`.

- [ ] **Step 4: Commit metadata and values changes**

```bash
git add Chart.yaml values.yaml
git commit -m "feat(agentgateway-bootstrap): upgrade agentgateway to 1.4.1 and bump chart to 0.5.0"
```

---

### Task 2: Update Documentation

**Files:**
- Modify: `charts/agentgateway-bootstrap/README.md:3,12,14`

**Interfaces:**
- Consumes: Updated chart metadata and default values from Task 1.
- Produces: Updated `README.md`.

- [ ] **Step 1: Update `README.md`**

Update badges and default values in `README.md`:

```markdown
![Version: 0.5.0](https://img.shields.io/badge/Version-0.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.4.1](https://img.shields.io/badge/AppVersion-1.4.1-informational?style=flat-square)
```

And in values table:
```markdown
| agentgatewayChart.version | string | `"1.4.1"` |  |
| agentgatewayCrdsChart.version | string | `"1.4.1"` |  |
```

- [ ] **Step 2: Verify `README.md` alignment**

Ensure no leftover `1.3.1` or `0.4.11` references exist in `README.md`.

- [ ] **Step 3: Commit documentation update**

```bash
git add README.md
git commit -m "docs(agentgateway-bootstrap): update README for 0.5.0 and 1.4.1"
```

---

### Task 3: Final Verification

**Files:**
- Read-only check across chart files.

- [ ] **Step 1: Run `helm lint .`**

Run: `helm lint .`
Expected: `1 Chart(s) linted, 0 chart(s) failed`

- [ ] **Step 2: Run `helm template`**

Run: `helm template test .`
Expected: Successful output containing `targetRevision: "1.4.1"` for both `agentgateway-crds` and `agentgateway-helm` ArgoCD Applications.
