# centcom-satellite

![Version: 0.16.0](https://img.shields.io/badge/Version-0.16.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.65.0](https://img.shields.io/badge/AppVersion-v0.65.0-informational?style=flat-square)

A lightweight Kubernetes helper service for webhook-triggered cluster operations

**Homepage:** <https://github.com/loafoe/centcom-satellite>

## Installing

Recommended — a reviewed values file and a pinned chart version:

```bash
helm upgrade --install centcom-satellite oci://ghcr.io/philips-software/helm-charts/centcom-satellite \
  -n centcom-satellite --create-namespace --version <chart-version> -f values.yaml
```

A convenience one-liner also exists — it auto-discovers cluster settings (SPIRE class,
Gateway, base domain, cluster name, AWS/IRSA details) and runs the equivalent
`helm upgrade --install` for you, so you don't have to hand-author a values file from
scratch:

```bash
curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/centcom-satellite/install.sh | bash
```

It defaults to a read-only install; pass `WRITE_MODE=true` to enable mutating features.
Fetch and read the script before piping it to `bash` rather than running it sight-unseen —
see the next section for how to actually verify it.

## Verifying `install.sh` before running it

Every chart this repo publishes to `oci://ghcr.io/philips-software/helm-charts/*` is
cosign-signed (keyless, GitHub Actions OIDC) as of chart `0.16.0`, and `install.sh` ships
bundled inside the chart it belongs to. That means a fetched copy of the script can be
checked against the exact signed artifact CI built — without trusting anything in the
fetched file itself.

`install.sh verify` automates this check, but **don't rely on that command alone** if you
genuinely don't trust the copy you fetched — a tampered script could just as easily fake
its own `verify` subcommand to always report success, since it would be running code from
the very file in question. The commands below perform the same checks independently, using
only `cosign`, `helm`, and `diff` — none of which come from the file being checked:

```bash
# 1. Fetch the script. Don't pipe straight to bash.
curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/centcom-satellite/install.sh -o install.sh

# 2. Read the chart version it claims to have shipped in — a plain grep, not execution.
VERSION=$(grep -o '^INSTALL_SH_CHART_VERSION="[^"]*"' install.sh | cut -d'"' -f2)
echo "install.sh claims chart version: $VERSION"

# 3. Independently verify that exact chart version's signature.
cosign verify "ghcr.io/philips-software/helm-charts/centcom-satellite:${VERSION}" \
  --certificate-identity-regexp="https://github.com/philips-software/helm-charts/.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"

# 4. Pull that exact signed chart and extract the install.sh bundled inside it.
mkdir -p /tmp/centcom-satellite-verify && cd /tmp/centcom-satellite-verify
helm pull "oci://ghcr.io/philips-software/helm-charts/centcom-satellite" --version "$VERSION"
tar -xzf centcom-satellite-*.tgz

# 5. Diff the canonical copy against the one you fetched. No output means identical.
diff centcom-satellite/install.sh /path/to/your/install.sh && echo "MATCH — safe to run"
```

If step 3 fails, or step 5 reports any difference, stop — do not run the script you
fetched. Requires `cosign` (<https://docs.sigstore.dev/cosign/installation/>) and `helm`
on `PATH`; needs no credentials for a public chart repository.

## Source Code

* <https://github.com/loafoe/centcom-satellite>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| aws.assumeRole.externalId | string | `""` |  |
| aws.assumeRole.region | string | `""` |  |
| aws.assumeRole.roleArn | string | `""` |  |
| aws.assumeRole.sessionName | string | `"centcom-satellite"` |  |
| aws.irsa.accountId | string | `""` |  |
| aws.irsa.audience | string | `"sts.amazonaws.com"` |  |
| aws.irsa.enabled | bool | `false` |  |
| aws.irsa.extraPolicyArns | list | `[]` |  |
| aws.irsa.namePrefix | string | `""` |  |
| aws.irsa.oidcIssuer | string | `""` |  |
| aws.irsa.path | string | `"/"` |  |
| aws.irsa.providerConfigRef | string | `"default"` |  |
| aws.irsa.region | string | `""` |  |
| aws.irsa.roleArnOverride | string | `""` |  |
| aws.irsa.tags | object | `{}` |  |
| features.argocd | bool | `false` |  |
| features.autoRemediate | bool | `false` |  |
| features.cloudwatchRca | bool | `false` |  |
| features.configmapRead | bool | `false` |  |
| features.getResource | bool | `false` |  |
| features.guardduty | bool | `false` |  |
| features.httpRequest | bool | `false` |  |
| features.nodeclaimDelete | bool | `false` |  |
| features.podEvict | bool | `false` |  |
| features.podResize | bool | `false` |  |
| features.podResizeAbsoluteCap | string | `"4Gi"` |  |
| features.podResizePercentageCap | int | `50` |  |
| features.pvResize | bool | `false` |  |
| features.securityhub | bool | `false` |  |
| features.securityhubWrite | bool | `false` |  |
| features.workloadRestart | bool | `false` |  |
| features.workloadScale | bool | `false` |  |
| fullnameOverride | string | `""` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.gatewayRef.name | string | `"platform"` |  |
| httpRoute.gatewayRef.namespace | string | `"kube-system"` |  |
| httpRoute.gatewayRef.sectionName | string | `""` |  |
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
| replicaCount | int | `2` |  |
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
| spire.jwt.bundleSource | string | `"workload_api"` |  |
| spire.jwt.enabled | bool | `false` |  |
| spire.jwt.federationBundleEndpoints | object | `{}` |  |
| spire.jwt.federationCABundlePath | string | `""` |  |
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
