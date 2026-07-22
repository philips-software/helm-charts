# agentgateway-bootstrap Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete Helm wrapper chart `agentgateway-bootstrap` for bootstrapping agentgateway with Amazon Bedrock support on Kubernetes via ArgoCD Applications.

**Architecture:** 
The chart uses ArgoCD Application CRs organized into sync waves:
- Wave 0: `agentgateway-crds` chart (`oci://cr.agentgateway.dev/charts/agentgateway-crds`)
- Wave 1: `agentgateway` control plane & proxy (`oci://cr.agentgateway.dev/charts/agentgateway`)
- Wave 2: Amazon Bedrock Gateway API resources (`AgentgatewayBackend`, `Gateway`, `HTTPRoute`).

**Tech Stack:** Helm 3, Kubernetes Gateway API, ArgoCD, Amazon Bedrock.

## Global Constraints
- Target directory: `charts/agentgateway-bootstrap/`
- Upstream charts: `oci://cr.agentgateway.dev/charts/agentgateway-crds` and `oci://cr.agentgateway.dev/charts/agentgateway` version `1.3.1`
- Exclude `agentgateway-bootstrap` in `ct.yaml`

---

### Task 1: Scaffolding Chart Metadata and Helper Templates

**Files:**
- Create: `charts/agentgateway-bootstrap/Chart.yaml`
- Create: `charts/agentgateway-bootstrap/templates/_helpers.tpl`
- Modify: `ct.yaml`

**Interfaces:**
- Produces: Standard Helm helpers for chart labeling, naming, and string variable substitution (`resourcePrefix`, `region`, `accountId`).

- [ ] **Step 1: Create Chart.yaml**
- [ ] **Step 2: Create templates/_helpers.tpl**
- [ ] **Step 3: Update ct.yaml**
- [ ] **Step 4: Verify with `helm lint`**

---

### Task 2: Chart Values and Configuration Template

**Files:**
- Create: `charts/agentgateway-bootstrap/values.yaml`
- Create: `charts/agentgateway-bootstrap/config/agentgateway-values.yaml`

**Interfaces:**
- Produces: Values configuration for `agentgateway-bootstrap` and `config/agentgateway-values.yaml` template used by ArgoCD Application.

- [ ] **Step 1: Create values.yaml**
- [ ] **Step 2: Create config/agentgateway-values.yaml**
- [ ] **Step 3: Verify syntax**

---

### Task 3: ArgoCD Application Templates for CRDs and Control Plane

**Files:**
- Create: `charts/agentgateway-bootstrap/templates/agentgateway-crds-helm.yaml`
- Create: `charts/agentgateway-bootstrap/templates/agentgateway-helm.yaml`

**Interfaces:**
- Consumes: `.Values.agentgatewayCrdsChart`, `.Values.agentgatewayChart`, `.Values.argoProject`.
- Produces: ArgoCD Application resources for Wave 0 and Wave 1 deployment.

- [ ] **Step 1: Create agentgateway-crds-helm.yaml (Sync Wave 0)**
- [ ] **Step 2: Create agentgateway-helm.yaml (Sync Wave 1)**
- [ ] **Step 3: Verify rendering with `helm template`**

---

### Task 4: Amazon Bedrock Gateway API Templates (Wave 2)

**Files:**
- Create: `charts/agentgateway-bootstrap/templates/bedrock-backend.yaml`
- Create: `charts/agentgateway-bootstrap/templates/gateway.yaml`
- Create: `charts/agentgateway-bootstrap/templates/httproute.yaml`

**Interfaces:**
- Consumes: `.Values.bedrock`, `.Values.environmentConfig`.
- Produces: AgentgatewayBackend (`ai.provider.bedrock`), Gateway (`agentgateway`), and HTTPRoute (`/bedrock` and `/v1/chat/completions`).

- [ ] **Step 1: Create bedrock-backend.yaml**
- [ ] **Step 2: Create gateway.yaml**
- [ ] **Step 3: Create httproute.yaml**
- [ ] **Step 4: Verify rendering with `helm template`**

---

### Task 5: Documentation and Verification

**Files:**
- Create: `charts/agentgateway-bootstrap/README.md.gotmpl`
- Create: `charts/agentgateway-bootstrap/README.md`

**Interfaces:**
- Produces: User documentation for chart deployment and configuration options.

- [ ] **Step 1: Create README.md.gotmpl**
- [ ] **Step 2: Generate README.md**
- [ ] **Step 3: Run helm lint and helm template validation across all configurations**
