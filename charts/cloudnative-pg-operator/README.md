# CloudNativePG Operator Helm Chart

A Helm chart for bootstrapping the CloudNativePG operator with Kyverno policies for image management.

## Overview

This chart deploys:

- **CloudNativePG Operator** via an ArgoCD Application
- **ClusterImageCatalog** for managing PostgreSQL images
- **Kyverno ClusterPolicy** to enforce image catalog usage and operator image

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- Kyverno installed (if using the Kyverno policy)
- Helm 3.x

## Configuration

### Required Values

| Parameter | Description |
|-----------|-------------|
| `environmentConfig.resourcePrefix` | Environment-specific resource prefix |
| `imageCatalog.images[].image` | PostgreSQL image URL (when imageCatalog is enabled) |
| `kyvernoPolicy.operatorImage` | Operator image URL (when kyvernoPolicy is enabled) |

### Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cnpgChart.version` | CloudNativePG Helm chart version | `0.27.0` |
| `environmentConfig.resourcePrefix` | Resource prefix for environment | `""` |
| `argoProject` | ArgoCD project name | `default` |
| `operator.fullnameOverride` | Override for operator deployment name | `cloudnative-pg` |
| `operator.namespace` | Namespace for the operator | `cnpg-system` |
| `operator.resources` | Resource limits/requests for operator | See values.yaml |
| `imageCatalog.enabled` | Enable ClusterImageCatalog | `true` |
| `imageCatalog.name` | Name of the ClusterImageCatalog | `default` |
| `imageCatalog.images` | List of PostgreSQL images | `[]` |
| `kyvernoPolicy.enabled` | Enable Kyverno mutation policy | `true` |
| `kyvernoPolicy.operatorImage` | Operator image for Kyverno policy | `""` |

## Example Usage

```yaml
environmentConfig:
  resourcePrefix: "prod"

argoProject: default

imageCatalog:
  enabled: true
  name: default
  images:
    - major: 18
      image: "${sharedServicesAccountId}.dkr.ecr.${region}.amazonaws.com/github/cloudnative-pg/postgresql:18.1-system-trixie"

kyvernoPolicy:
  enabled: true
  operatorImage: "${sharedServicesAccountId}.dkr.ecr.${region}.amazonaws.com/github/cloudnative-pg/cloudnative-pg:1.28.0"
```

## Installation

```bash
helm install cloudnative-pg-operator ./cloudnative-pg-operator \
  --namespace argocd \
  --values my-values.yaml
```
