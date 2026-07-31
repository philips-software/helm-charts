# Agentgateway 1.4.1 Bootstrap Wrapper Upgrade Design

## Overview
This design document details the updates to `agentgateway-bootstrap` Helm chart to support upstream `agentgateway` version `1.4.1`.

## Upstream Release Highlights (1.4.0 / 1.4.1)
- Gateway API v1.6 support (using `v1` version of `TCPRoute`).
- Protocol support for MCP 2026-07-28.
- Enterprise-Managed Authorization (Cross App Access via OAuth ID-JAG).
- Refreshed UI, model-based routing, and cost catalog enhancements.
- Bug fixes and security patches in 1.4.1.

## Changes Required

### 1. `Chart.yaml`
- Update `version` from `0.4.11` to `0.5.0`.
- Update `appVersion` from `"1.3.1"` to `"1.4.1"`.

### 2. `values.yaml`
- `agentgatewayCrdsChart.version`: `1.4.1`
- `agentgatewayChart.version`: `1.4.1`

### 3. `README.md`
- Update version badges to `0.5.0` and `1.4.1`.
- Update default table entries for `agentgatewayChart.version` and `agentgatewayCrdsChart.version`.

## Verification & Testing Strategy
- Execute `helm lint .` to confirm chart syntax validity.
- Execute `helm template test .` to verify clean manifest generation for ArgoCD Applications and bootstrap CRDs.
