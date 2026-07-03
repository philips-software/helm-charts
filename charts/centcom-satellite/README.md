# centcom-satellite

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.49.1](https://img.shields.io/badge/AppVersion-v0.49.1-informational?style=flat-square)

A lightweight Kubernetes helper service for webhook-triggered cluster operations

**Homepage:** <https://github.com/loafoe/centcom-satellite>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Andy Lo-A-Foe | <andy.lo-a-foe@philips.com> |  |

## Source Code

* <https://github.com/loafoe/centcom-satellite>

## CloudWatch RCA Feature

The chart supports AWS CloudWatch Root Cause Analysis (RCA) tasks when `features.cloudwatchRca` is enabled. This feature allows centcom-satellite to perform CloudWatch alarm analysis, metric queries, CloudWatch Logs Insights queries, and AWS Cost Explorer queries.

### Prerequisites

- Crossplane `provider-aws-iam` (v2.6.0 or later) installed in the cluster
- A `ClusterProviderConfig` named `default` configured with AWS credentials (typically IRSA-based)
- An OIDC identity provider configured in your AWS account for Kubernetes service account federation
- A pod-identity webhook or EKS Pod Identity Agent to inject AWS credentials into pods

### IRSA Configuration

When `aws.irsa.enabled` is true, the chart will:

1. Create a Crossplane-managed IAM Policy with permissions for CloudWatch, CloudWatch Logs, and Cost Explorer APIs
2. Create a Crossplane-managed IAM Role with a trust policy for your cluster's OIDC provider
3. Attach the policy to the role via a Crossplane RolePolicyAttachment
4. Annotate the ServiceAccount with `eks.amazonaws.com/role-arn` for IRSA injection
5. Set `AWS_REGION` environment variable on the pod

When `aws.irsa.roleArnOverride` is set, the chart creates no IAM resources (no Crossplane Policy/Role/Attachment) and only annotates the ServiceAccount with the provided role ARN. You are responsible for that role's policy and trust relationship.

The pod-identity webhook will inject `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables, plus the projected service account token volume.

### Example Installation

```bash
helm upgrade --install centcom-satellite philips-software/centcom-satellite \
  --namespace centcom-satellite \
  --create-namespace \
  --set features.cloudwatchRca=true \
  --set aws.irsa.enabled=true \
  --set aws.irsa.accountId=123456789012 \
  --set aws.irsa.oidcIssuer=oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE \
  --set aws.irsa.region=us-west-2
```

### IAM Permissions

The Crossplane-managed policy grants the following permissions:

- `cloudwatch:DescribeAlarms` - List and describe CloudWatch alarms
- `cloudwatch:DescribeAlarmHistory` - Retrieve alarm state change history
- `cloudwatch:GetMetricData` - Query CloudWatch metrics
- `cloudwatch:ListMetrics` - List available metrics
- `logs:DescribeLogGroups` - List CloudWatch log groups
- `logs:StartQuery` - Start CloudWatch Logs Insights queries
- `logs:GetQueryResults` - Retrieve query results
- `logs:StopQuery` - Cancel running queries
- `ce:GetCostAndUsage` - Query AWS Cost Explorer data

All actions are granted on all resources (`"Resource": "*"`). Customize the policy by overriding the Crossplane Policy template if needed.

### Verification

After deployment, verify the IRSA setup:

```bash
# Check that Crossplane resources are SYNCED and READY
kubectl -n <namespace> get policy.iam.aws.m.upbound.io,role.iam.aws.m.upbound.io,rolepolicyattachment.iam.aws.m.upbound.io

# Verify the ServiceAccount annotation
kubectl -n <namespace> get sa -o yaml | grep eks.amazonaws.com/role-arn

# Confirm AWS environment variables are injected in the pod
kubectl -n <namespace> exec deploy/centcom-satellite -- env | grep AWS_
```

The pod should show:
- `AWS_ROLE_ARN=arn:aws:iam::<accountId>:role/<release-name>-cw-rca`
- `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- `AWS_REGION=<configured region>`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| aws.irsa.accountId | string | `""` | AWS account ID for computing IRSA role ARN |
| aws.irsa.audience | string | `"sts.amazonaws.com"` | Token audience expected in IRSA trust policy |
| aws.irsa.enabled | bool | `false` | Create Crossplane IAM resources and annotate ServiceAccount for IRSA |
| aws.irsa.oidcIssuer | string | `""` | Cluster OIDC issuer host (no scheme) |
| aws.irsa.path | string | `"/"` | IAM path for Policy and Role; automatically incorporated into the role ARN |
| aws.irsa.providerConfigRef | string | `"default"` | Crossplane ClusterProviderConfig name |
| aws.irsa.region | string | `""` | AWS region for CloudWatch/Logs API calls |
| aws.irsa.roleArnOverride | string | `""` | Bring-your-own role ARN; skips creating Crossplane IAM resources |
| aws.irsa.tags | object | `{}` | Extra tags applied to IAM Policy and Role |
| features.argocd | bool | `false` |  |
| features.autoRemediate | bool | `false` |  |
| features.cloudwatchRca | bool | `false` | Enable CloudWatch RCA tasks (requires AWS credentials) |
| features.configmapRead | bool | `false` |  |
| features.getResource | bool | `false` |  |
| features.httpRequest | bool | `false` |  |
| features.nodeclaimDelete | bool | `false` |  |
| features.podEvict | bool | `false` |  |
| features.podResize | bool | `false` |  |
| features.podResizeAbsoluteCap | string | `"4Gi"` |  |
| features.podResizePercentageCap | int | `50` |  |
| features.pvResize | bool | `false` |  |
| features.workloadRestart | bool | `false` |  |
| features.workloadScale | bool | `false` |  |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.gatewayRef.name | string | `"platform"` |  |
| httpRoute.gatewayRef.namespace | string | `"kube-system"` |  |
| httpRoute.gatewayRef.sectionName | string | `"http-0"` |  |
| httpRoute.hostname | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/loafoe/centcom-satellite"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| nodeSelector."kubernetes.io/os" | string | `"linux"` |  |
| observability.logFormat | string | `"json"` |  |
| observability.logLevel | string | `"info"` |  |
| observability.otelEndpoint | string | `""` |  |
| observability.otelInsecure | bool | `true` |  |
| observability.otelServiceName | string | `"centcom-satellite"` |  |
| podAnnotations | object | `{}` |  |
| podSecurityContext.fsGroup | int | `65532` |  |
| podSecurityContext.runAsGroup | int | `65532` |  |
| podSecurityContext.runAsNonRoot | bool | `true` |  |
| podSecurityContext.runAsUser | int | `65532` |  |
| podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| rbac.additionalRules | list | `[]` |  |
| rbac.create | bool | `true` |  |
| replicaCount | int | `1` |  |
| resources.limits.cpu | string | `"100m"` |  |
| resources.limits.memory | string | `"128Mi"` |  |
| resources.requests.cpu | string | `"10m"` |  |
| resources.requests.memory | string | `"32Mi"` |  |
| securityContext.allowPrivilegeEscalation | bool | `false` |  |
| securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| securityContext.readOnlyRootFilesystem | bool | `true` |  |
| service.metricsPort | int | `9090` |  |
| service.port | int | `8080` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| serviceMonitor.enabled | bool | `false` |  |
| serviceMonitor.honorLabels | bool | `false` |  |
| serviceMonitor.interval | string | `"30s"` |  |
| serviceMonitor.labels | object | `{}` |  |
| serviceMonitor.metricRelabelings | list | `[]` |  |
| serviceMonitor.namespace | string | `""` |  |
| serviceMonitor.relabelings | list | `[]` |  |
| serviceMonitor.scrapeTimeout | string | `"10s"` |  |
| serviceMonitor.targetLabels | list | `[]` |  |
| spire.agentSocket | string | `"unix:///spiffe-workload-api/spire-agent.sock"` |  |
| spire.allowedSPIFFEIDs | list | `[]` |  |
| spire.className | string | `"spire-release-spire"` |  |
| spire.csi.enabled | bool | `true` |  |
| spire.enabled | bool | `true` |  |
| spire.hostSocketPath | string | `"/run/spire/agent-sockets"` |  |
| spire.jwt.audiences | list | `[]` |  |
| spire.jwt.enabled | bool | `false` |  |
| spire.localTrustDomain | string | `""` |  |
| spire.mtlsEnabled | bool | `false` |  |
| spire.skipFederation | bool | `false` |  |
| spire.socketMountPath | string | `"/spiffe-workload-api"` |  |
| spire.trustDomain | string | `""` |  |
| spire.trustDomains | list | `[]` |  |
| tolerations | list | `[]` |  |
| vpa.enabled | bool | `true` |  |
| vpa.inPlaceResize | bool | `false` |  |
| vpa.maxAllowed.cpu | string | `"500m"` |  |
| vpa.maxAllowed.memory | string | `"1Gi"` |  |
| vpa.minAllowed.cpu | string | `"5m"` |  |
| vpa.minAllowed.memory | string | `"16Mi"` |  |
| vpa.minReplicas | int | `1` |  |
| vpa.updateMode | string | `"InPlaceOrRecreate"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
