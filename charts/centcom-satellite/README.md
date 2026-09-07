# centcom-satellite

![Version: 0.22.1](https://img.shields.io/badge/Version-0.22.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.68.0](https://img.shields.io/badge/AppVersion-v0.68.0-informational?style=flat-square)

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
see the next section for how to actually verify it. To hand the actual `helm` step to
someone else instead of running it yourself, pass `VALUES_ONLY=true` — the script still
auto-discovers everything but only renders `values.yaml` plus the equivalent
`helm upgrade --install -f values.yaml` command, without touching the cluster (see the
[configuration reference](#installsh-configuration-reference) below for the full list of
overrides).

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

## `install.sh` configuration reference

Every setting below is an environment variable read by `install.sh` (not a Helm value —
see [Values](#values) for those). Anything left unset is either auto-discovered from the
target cluster or defaulted to the safe/read-only choice; nothing is prompted interactively.
Pass overrides the same way as the examples above, e.g.:

```bash
curl -fsSL .../install.sh | CLUSTER_NAME=edge AGENTLESS=true bash
```

### Rendering values instead of installing

| Variable | Default | Description |
|----------|---------|--------------|
| `VALUES_ONLY` | `false` | When `true`, runs every auto-discovery step as normal but never touches the cluster: it dry-runs the resolved `helm upgrade --install` through Helm itself, writes the merged `values.yaml` to disk, and prints the equivalent plain `helm upgrade --install -f <file>` command on stdout for you to run by hand. Skips `confirm_countdown`, `configure_federation`, `adopt_orphans`, `deploy`, `normalize_route`, `configure_ingress`, and `verify` entirely. Note: the `ClusterFederatedTrustDomain` (unless `AGENTLESS=true`) and the nginx `Ingress` (if `USE_INGRESS=true`) are plain `kubectl` manifests outside the chart, so they are *not* captured in the rendered file — apply them yourself or re-run without `VALUES_ONLY`. |
| `VALUES_FILE` | `<release-name>-values.yaml` | Output path for the rendered values file when `VALUES_ONLY=true`. |

### centcom federation (the caller this satellite trusts)

| Variable | Default | Description |
|----------|---------|--------------|
| `MCP_TRUST_DOMAIN` | `dip-ce-k3s-eu.hsp.philips.com` | Trust domain of the centcom cluster calling this satellite. |
| `MCP_BUNDLE_ENDPOINT` | `https://spiffe.dip-ce-k3s-eu.hsp.philips.com:8443` | SPIFFE Federation Bundle Endpoint for `MCP_TRUST_DOMAIN`. Also reused as the URL `AGENTLESS=true` polls directly. |
| `MCP_SPIFFE_ID` | `spiffe://dip-ce-k3s-eu.hsp.philips.com/ns/centcom/sa/centcom` | SPIFFE ID of the centcom caller, added to `spire.allowedSPIFFEIDs`. |
| `MCP_FEDERATION_NAME` | `dip-ce-k3s-eu` | Name of the `ClusterFederatedTrustDomain` this script applies. |

### Optional local caller (same trust domain, same cluster)

| Variable | Default | Description |
|----------|---------|--------------|
| `LOCAL_SPIFFE_ID` | *(empty)* | SPIFFE ID of a centcom running in the *same* cluster/trust domain as this satellite. Added to the accept-list without federation. Unsupported together with `AGENTLESS=true`. |
| `LOCAL_TRUST_DOMAIN` | *(empty)* | Trust domain for `LOCAL_SPIFFE_ID`. Auto-discovered from the SPIFFE ID or the local `spire-server` config if unset. |

### SPIRE agent-less mode

| Variable | Default | Description |
|----------|---------|--------------|
| `AGENTLESS` | *(auto)* | Force JWT-SVID validation via a federation-bundle HTTPS fetch instead of the local SPIRE Workload API — no agent socket, no `ClusterFederatedTrustDomain`, no CSI driver. Auto-enabled when the cluster has no SPIRE controller-manager (`clusterspiffeids` CRD absent); pass `AGENTLESS=false` to force the workload-API path anyway. Incompatible with `LOCAL_SPIFFE_ID` and with `spire.mtlsEnabled`. |

### Install target

| Variable | Default | Description |
|----------|---------|--------------|
| `NAMESPACE` | `centcom-satellite` | Target namespace. |
| `RELEASE_NAME` | `centcom-satellite` | Helm release name. |
| `CHART` | `oci://ghcr.io/philips-software/helm-charts/centcom-satellite` | Chart reference (OCI ref or local path). |
| `CHART_VERSION` | *(empty = latest)* | Pin a specific chart version. |
| `IMAGE_TAG` | *(empty = chart's appVersion)* | Override the container image tag. |

### Read-only vs. write mode

| Variable | Default | Description |
|----------|---------|--------------|
| `READ_ONLY` | `true` (when nothing set) | Explicit `true` always forces read-only, regardless of `WRITE_MODE`. Accepted as a synonym of `WRITE_MODE=false`. |
| `WRITE_MODE` | *(empty)* | Set `true` to enable every mutating feature (`workloadRestart`, `workloadScale`, `podEvict`, `podResize`, `nodeclaimDelete`, `pvResize`, `autoRemediate`, `securityhubWrite` if requested) except `getResource` (wildcard-read, opt-in separately). With nothing set at all the installer defaults to read-only. |
| `FEATURES` | *(derived from `READ_ONLY`)* | Raw override of the `features.*` Helm values as a comma-separated `key=value` list, e.g. `FEATURES=getResource=true,argocd=true`. Rarely needed directly — prefer `WRITE_MODE`/`READ_ONLY` and the AWS task-group flags below. |

### AWS-backed task groups (CloudWatch RCA / GuardDuty / Security Hub)

All of these provision the same generic Crossplane-managed IAM role via IRSA; any one of them enables the IRSA plumbing.

| Variable | Default | Description |
|----------|---------|--------------|
| `IRSA_ENABLED` | *(auto)* | Master switch: `true` turns on every unset AWS **read-only** task group below (never `SECURITYHUB_WRITE`, which stays opt-in). Auto-`true` when any individual group is explicitly `true`. |
| `CLOUDWATCH_RCA` | `false` | Enable CloudWatch RCA + Cost Explorer tasks (7 read-only tasks). |
| `GUARDDUTY` | `false` | Enable GuardDuty read tasks (5 tasks: detectors, findings statistics, list/get findings, hydrate composite). |
| `SECURITYHUB` | `false` | Enable Security Hub read tasks (list standards, get findings, findings statistics). Aggregates more products than GuardDuty alone. |
| `SECURITYHUB_WRITE` | `false` | Enable `securityhub_update_findings` (`BatchUpdateFindings`). Read+write, not write-only — implies `SECURITYHUB=true` automatically. Force-disabled whenever `READ_ONLY=true`, regardless of how it's set. |

### IRSA / AWS identity (all auto-discovered from the target cluster)

| Variable | Default | Description |
|----------|---------|--------------|
| `IRSA_ACCOUNT_ID` | *(auto)* | AWS account ID, discovered from an existing IRSA-annotated ServiceAccount (majority vote, excluding this release's own SA and the AWS-docs placeholder account). |
| `IRSA_OIDC_ISSUER` | *(auto)* | Cluster OIDC issuer host (scheme stripped), from `/.well-known/openid-configuration`. |
| `IRSA_REGION` | *(auto)* | AWS region, from a node's `topology.kubernetes.io/region` label or `providerID`. |
| `IRSA_PROVIDER_CONFIG` | *(auto)* | Crossplane `ClusterProviderConfig` name — prefers one named `default`. |
| `IRSA_AUDIENCE` | `sts.amazonaws.com` | Token audience for the IRSA trust policy. |
| `IRSA_ROLE_ARN` | *(empty)* | Bring-your-own IAM role ARN — skips Crossplane role creation entirely. |
| `IRSA_NAME_PREFIX` | *(auto: `CLUSTER_NAME`, sanitized)* | Disambiguates the AWS-global IAM Role/Policy names when multiple clusters share an AWS account. Set empty to opt out (pre-existing, un-prefixed naming). |

### Cross-account AWS AssumeRole

See `CROSS-ACCOUNT-ASSUMEROLE.md` in the innovation-day repo for the full onboarding runbook — not exposed as `install.sh` flags; configure `aws.assumeRole.*` directly in a values file (see [Values](#values)).

### Networking / exposure

| Variable | Default | Description |
|----------|---------|--------------|
| `USE_INGRESS` | *(auto)* | Use an nginx `Ingress` instead of a Gateway API `HTTPRoute` — for clusters whose gateway has a broken http-to-https redirect. Fails fast if no `IngressClass` exists. Mutually exclusive with `HTTPROUTE_ENABLED`. |
| `HTTPROUTE_ENABLED` | `true` (unless `USE_INGRESS=true`) | Explicitly force/disable the Gateway API `HTTPRoute` path. Leaving both this and `USE_INGRESS` unset auto-detects: no Gateway API CRD → nginx Ingress if available, else ClusterIP-only with a warning. |
| `GATEWAY_NAME` | *(auto)* | Gateway to attach to — prefers one named `gateway` or `platform`, else the first found. |
| `GATEWAY_NAMESPACE` | *(auto)* | Namespace of the chosen Gateway. |
| `GATEWAY_SECTION` | *(empty — intentionally not auto-set)* | Gateway listener `sectionName`. Leave empty to attach to all listeners; setting one can cause redirect loops on gateways with an all-listener http-to-https-redirect route. |
| `HOSTNAME_FQDN` | *(auto: `centcom-satellite.<BASE_DOMAIN>`)* | Full hostname for the route. |
| `BASE_DOMAIN` | *(auto: most common existing route hostname suffix)* | Base domain used to build `HOSTNAME_FQDN`. |
| `INGRESS_CLASS` | *(auto, `USE_INGRESS=true` only)* | `IngressClass` — prefers one named `nginx`, else the first found. |
| `CLUSTER_ISSUER` | *(auto, `USE_INGRESS=true` only)* | cert-manager `ClusterIssuer` — prefers one whose name contains `prod`. |
| `INGRESS_TLS_SECRET` | `centcom-satellite-tls` | TLS secret name for the nginx `Ingress`. |

### Identity

| Variable | Default | Description |
|----------|---------|--------------|
| `CLUSTER_NAME` | *(auto: hsp-addons environment tag, else kube-context name)* | Identifies this cluster (used in `JWT_AUDIENCE`, `IRSA_NAME_PREFIX`, log/summary output). |
| `SPIRE_CLASSNAME` | *(auto, skipped under `AGENTLESS=true`)* | SPIRE controller-manager `className` — the most common one found among existing `ClusterSPIFFEID`s. |
| `JWT_AUDIENCE` | *(auto: `centcom-satellite-<CLUSTER_NAME>`)* | Expected JWT-SVID audience. |

### Behavior / sizing

| Variable | Default | Description |
|----------|---------|--------------|
| `SERVICEMONITOR_ENABLED` | *(auto)* | Force on/off; unset auto-detects the Prometheus Operator CRD. |
| `VPA_ENABLED` | *(auto)* | Force on/off; unset auto-detects the VPA CRD. |
| `REPLICA_COUNT` | `2` | Pod replica count. |
| `POD_COUNT` | *(auto: cluster-wide pod count)* | Skips the live pod-count query when set — useful on locked-down/huge clusters. Drives the memory tier table below. |
| `MEMORY_LIMIT` | *(auto, tiered from `POD_COUNT`)* | Force the initial memory limit (e.g. `512Mi`); the VPA ceiling still tiers unless `VPA_MAX_MEMORY` is also set. |
| `VPA_MAX_MEMORY` | *(auto, tiered from `POD_COUNT`)* | Force the VPA memory ceiling (e.g. `4Gi`). |
| `DRY_RUN` | `false` | Print every helm/kubectl action instead of running it — nothing changes. Unlike `VALUES_ONLY`, does not write a values file. |
| `WAIT_TIMEOUT` | `180s` | Timeout for `helm --wait` and the post-install rollout check. |
| `COUNTDOWN` | *(auto, 8–20s from plan size)* | Seconds to review the resolved plan before installing; `ESC` aborts, `ENTER` proceeds immediately. |
| `ASSUME_YES` | `false` | Skip the review countdown entirely (CI / unattended runs). |
| `ADOPT_RESOURCES` | `true` | Stamp Helm ownership onto pre-existing chart resources that lack it, so `helm upgrade` can adopt them. |
| `FORCE_CONFLICTS` | `true` | Use server-side apply + `--force-conflicts` so the upgrade reclaims fields another manager grabbed (e.g. a manual `kubectl scale`). Requires Helm 3.18+/4.x; falls back with a warning on older Helm. |

### Diagnostics

| Variable | Default | Description |
|----------|---------|--------------|
| `TRACE` | `false` | Full `bash -x` command tracing. |
| `LOG_STDOUT` | `auto` | `auto` merges stderr into stdout only when stdout isn't a terminal (a CI runner capturing output); `true`/`false` force one behavior regardless. Only the final copy/paste snippet (or, under `VALUES_ONLY`, the `helm` command) is ever stdout-only by design. |

## Source Code

* <https://github.com/loafoe/centcom-satellite>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod scheduling |
| aws.assumeRole.externalId | string | `""` | Optional STS ExternalId, passed to AssumeRole for confused-deputy protection. Only needed if the target role's trust policy requires one. |
| aws.assumeRole.region | string | `""` | Overrides the AWS region used for AssumeRole'd API calls. Only applies while roleArn is set — a cluster-less satellite's pod region has no necessary relationship to the target account's region, so this can't fall back to aws.irsa.region (which describes the pod's own cluster). |
| aws.assumeRole.roleArn | string | `""` | Target IAM role ARN in a different AWS account. Empty (default) disables the feature entirely — every AWS task keeps using the base IRSA identity, byte-for-byte unchanged. |
| aws.assumeRole.sessionName | string | `"centcom-satellite"` | STS RoleSessionName, visible in the target account's CloudTrail. |
| aws.irsa.accountId | string | `""` | AWS account ID (used to compute the role ARN stamped on the ServiceAccount) |
| aws.irsa.audience | string | `"sts.amazonaws.com"` | Token audience expected in the IRSA trust policy |
| aws.irsa.enabled | bool | `false` | Create Crossplane IAM Role (+ per-feature Policy/Attachment) and annotate the SA for IRSA |
| aws.irsa.extraPolicyArns | list | `[]` | Additional pre-existing managed-policy ARNs to attach to the generic role. Use this to grant IAM for task groups beyond the built-in CloudWatch RCA policy without defining a new role, e.g.:   extraPolicyArns:     - arn:aws:iam::123456789012:policy/centcom-satellite-extra |
| aws.irsa.namePrefix | string | `""` | Prefix for the AWS-facing IAM resource names (Role, Policy). Unlike a Kubernetes object name, an IAM role/policy name is GLOBAL PER AWS ACCOUNT: two clusters that share one account and both install this chart would otherwise collide on the identical role/policy name (and role ARN). Set this to something cluster-unique to disambiguate them — install.sh seeds it from the cluster's environment tag (hsp-addons EnvironmentConfig). Empty == no prefix (role/policy named after the release), preserving the behaviour of installs that predate this option. |
| aws.irsa.oidcIssuer | string | `""` | Cluster OIDC issuer host (no scheme), e.g. k3s-issuer.dip-ce-k3s-eu.hsp.philips.com |
| aws.irsa.path | string | `"/"` | IAM path applied to the created role/policies |
| aws.irsa.providerConfigRef | string | `"default"` | Crossplane ClusterProviderConfig name |
| aws.irsa.region | string | `""` | AWS region the SDK uses for CloudWatch/Logs calls (Cost Explorer is us-east-1 in code) |
| aws.irsa.roleArnOverride | string | `""` | Bring-your-own role: when set, skip building the ARN from accountId and just annotate the SA with this ARN (Crossplane resources still render if enabled). |
| aws.irsa.tags | object | `{}` | Extra tags applied to the created role/policies |
| features.argocd | bool | `false` | Enable Argo CD application introspection. When enabled, grants get/list/watch on argoproj.io applications |
| features.autoRemediate | bool | `false` | Enable auto-remediation workflows orchestrated by centcom (e.g. PV usage alerting and automatic resize). Sets AUTO_REMEDIATE_ENABLED. |
| features.cloudwatchRca | bool | `false` | Enable CloudWatch RCA tasks (7 tasks: describe/list/tag APIs for alarms, metrics, log groups, Cost Explorer). Sets CLOUDWATCH_RCA_ENABLED. Requires AWS credentials via IRSA (aws.irsa) or ambient credentials. |
| features.getResource | bool | `true` | Enable get_resource task for fetching arbitrary Kubernetes resources |
| features.guardduty | bool | `false` | Enable GuardDuty tasks (5 tasks: list detectors, findings statistics, list/get findings, and a list+hydrate composite). Sets GUARDDUTY_ENABLED. Independently toggleable from cloudwatchRca. Requires AWS credentials via IRSA (aws.irsa) or ambient credentials; attaches the read-only GuardDuty policy to the IRSA role. |
| features.httpRequest | bool | `false` | Enable http_request task for making HTTP requests to cluster-internal services. Useful for admin endpoints, ring management, config reloads, debugging. Only allows requests to cluster-internal addresses (pods, services) |
| features.nodeclaimDelete | bool | `false` | Enable nodeclaim_delete task for Karpenter node management. When enabled, grants get/delete on karpenter.sh nodeclaims |
| features.podEvict | bool | `false` | Enable pod_evict task for evicting/deleting pods. When enabled, grants eviction create, pod delete, and read on PDBs |
| features.podResize | bool | `false` | Enable pod_resize task for in-place pod memory resize (KEP-1287). Requires Kubernetes 1.27+ with InPlacePodVerticalScaling feature gate |
| features.podResizeAbsoluteCap | string | `"4Gi"` | Pod resize safety limits: max absolute memory value allowed per resize call |
| features.podResizePercentageCap | int | `50` | Pod resize safety limits: max percentage change allowed per resize call |
| features.pvResize | bool | `false` | Enable pv_resize task for resizing persistent volumes. When enabled, grants patch permission on PVCs |
| features.resourceAccessDeny | list | `[]` | Additional group+kind pairs get_resource refuses to read, on top of the non-negotiable default (Secret). Empty by default. Example: resourceAccessDeny:   - group: "external-secrets.io"     kind: "SecretStore" |
| features.securityhub | bool | `false` | Enable Security Hub read tasks (list standards, get findings, get findings statistics). Sets SECURITYHUB_ENABLED. Independently toggleable from guardduty and cloudwatchRca — Security Hub aggregates findings from more products (GuardDuty, Inspector, Macie, IAM Access Analyzer, Config, custom integrations) than GuardDuty alone. Requires AWS credentials via IRSA (aws.irsa) or ambient credentials; attaches the read-only Security Hub policy to the IRSA role. |
| features.securityhubWrite | bool | `false` | Enable the securityhub_update_findings write task (BatchUpdateFindings — sets a finding's Workflow.Status and/or Note). Sets SECURITYHUB_WRITE_ENABLED. This is a read+write capability, not a write-only add-on: enabling it also sets SECURITYHUB_ENABLED and attaches the read-only Security Hub policy — you can enable securityhub alone for read-only triage visibility, but securityhubWrite always implies securityhub. Attaches an additional write-only Security Hub policy to the IRSA role (least privilege — BatchUpdateFindings only) on top of the read policy. |
| features.workloadRestart | bool | `false` | Enable workload_restart task for rolling restarts of deployments/statefulsets/daemonsets. When enabled, grants patch permission on apps workloads and read on PDBs |
| features.workloadScale | bool | `false` | Enable workload_scale task for scaling deployments/statefulsets. When enabled, grants scale subresource access and read on HPAs |
| fullnameOverride | string | `""` | Overrides the full generated release name |
| httpRoute.annotations | object | `{}` | Optional annotations on the HTTPRoute |
| httpRoute.enabled | bool | `false` | Enable HTTPRoute for external access |
| httpRoute.gatewayRef.name | string | `"platform"` | Name of the Gateway to attach to |
| httpRoute.gatewayRef.namespace | string | `"kube-system"` | Namespace of the Gateway to attach to |
| httpRoute.gatewayRef.sectionName | string | `""` | Empty (default) omits sectionName entirely, matching any listener on the Gateway. Only set this if the Gateway has multiple listeners and you need to pin to one by name — a stale/wrong name here fails the route with "No matching listener" (this default used to be the nonexistent "http-0"; every real install had to override it). |
| httpRoute.hostname | string | `""` | Hostname for the route |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"ghcr.io/loafoe/centcom-satellite"` | Container image repository |
| image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| imagePullSecrets | list | `[]` | Secrets for pulling the image from a private registry |
| nameOverride | string | `""` | Overrides the chart's name |
| nodeSelector | object | `{"kubernetes.io/os":"linux"}` | Node selector for pod scheduling |
| observability.logFormat | string | `"json"` | Log output format (json or console) |
| observability.logLevel | string | `"info"` | Log verbosity (e.g. debug, info, warn, error) |
| observability.otelEndpoint | string | `""` | OpenTelemetry OTLP collector endpoint for span export (host:port). When empty, spans are not exported but trace context is still propagated. |
| observability.otelInsecure | bool | `true` | Use plaintext (insecure) for the OTLP exporter. Set to false to use TLS. Maps to OTEL_EXPORTER_OTLP_INSECURE. Only applies when otelEndpoint is set. |
| observability.otelServiceName | string | `"centcom-satellite"` | Service name reported on exported OTLP spans |
| podAnnotations | object | `{}` | Extra annotations to add to the pod |
| podSecurityContext | object | `{"fsGroup":65532,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level securityContext |
| rateLimit.burst | int | `100` | Burst capacity above the sustained rate before throttling kicks in. |
| rateLimit.enabled | bool | `true` | Enable per-client-IP request throttling on the main HTTP server |
| rateLimit.requestsPerSecond | int | `50` | Sustained requests/second allowed per client IP. |
| rbac.additionalRules | list | `[]` | Additional RBAC rules to add to the ClusterRole. Example: additionalRules:   - apiGroups: ["custom.example.com"]     resources: ["myresources"]     verbs: ["get", "list", "watch"] |
| rbac.create | bool | `true` | Create ClusterRole and ClusterRoleBinding |
| replicaCount | int | `2` | Number of pod replicas |
| resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Container resource requests/limits. The initial memory.limit is sized for small/medium clusters; large clusters (thousands of pods, see observability.logLevel and vpa above) should raise this — install.sh's discover_memory tiers it automatically from cluster-wide pod count. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container-level securityContext |
| service.metricsPort | int | `9090` | Port serving Prometheus metrics at /metrics |
| service.port | int | `8080` | Port serving the main HTTP API (used by centcom / clients) |
| service.type | string | `"ClusterIP"` | Kubernetes Service type |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use |
| serviceMonitor.enabled | bool | `false` | Enable creation of a ServiceMonitor resource |
| serviceMonitor.honorLabels | bool | `false` | Keep metric labels from the target instead of overwriting on conflict |
| serviceMonitor.interval | string | `"30s"` | Scrape interval |
| serviceMonitor.labels | object | `{}` | Extra labels on the ServiceMonitor. Often required so the Prometheus Operator's serviceMonitorSelector picks it up, e.g. {release: kube-prometheus-stack} |
| serviceMonitor.metricRelabelings | list | `[]` | Prometheus relabeling applied to scraped samples (metric_relabel_configs) |
| serviceMonitor.namespace | string | `""` | Namespace for the ServiceMonitor (defaults to the release namespace). Set this when your Prometheus watches a specific namespace. |
| serviceMonitor.relabelings | list | `[]` | Prometheus relabeling applied before scraping (relabel_configs) |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Per-scrape timeout |
| serviceMonitor.targetLabels | list | `[]` | Service labels to copy onto scraped metrics as target labels |
| spire.agentSocket | string | `"unix:///spiffe-workload-api/spire-agent.sock"` | SPIRE agent socket path (env var passed to the application) |
| spire.allowedSPIFFEIDs | list | `[]` | List of allowed SPIFFE IDs (empty = allow all from configured trust domains). Example: ["spiffe://example.org/ai-agent", "spiffe://partner.com/service"] |
| spire.className | string | `"spire-release-spire"` | SPIRE controller manager className (must match your SPIRE installation). Common values: "spire-release-spire", "spire-system-spire" |
| spire.csi.enabled | bool | `true` | Enable the SPIFFE CSI driver volume mount for the agent socket (recommended over hostPath) |
| spire.enabled | bool | `true` | Enable SPIRE authentication (required for both mTLS and JWT modes) |
| spire.hostSocketPath | string | `"/run/spire/agent-sockets"` | Host path for SPIRE socket (used when csi.enabled=false) |
| spire.jwt.audiences | list | `[]` | Expected JWT audiences (at least one required when jwt.enabled=true). Example: ["centcom-satellite", "https://centcom-satellite.example.org"] |
| spire.jwt.bundleSource | string | `"workload_api"` | How the JWT trust bundle is obtained. "workload_api" (default) fetches it from the local SPIRE Workload API via the agent socket below — requires a local SPIRE Agent (CSI driver or hostPath). "federation" fetches it from a SPIFFE Federation Bundle Endpoint over HTTPS instead — no local SPIRE Agent required, so the chart skips the agent-socket volume/mount entirely. This is what makes ECS/Fargate-style targets (or any cluster without a SPIRE Agent DaemonSet) viable. Requires spire.mtlsEnabled=false — federation mode has no X.509 identity source. |
| spire.jwt.enabled | bool | `false` | Enable JWT-SVID validation |
| spire.jwt.federationBundleEndpoints | object | `{}` | Map of trust domain -> federation bundle endpoint URL. Required, with one entry per domain in spire.trustDomains, when bundleSource is "federation". Example:   federationBundleEndpoints:     example.org: "https://spire-server.example.org/bundle" |
| spire.jwt.federationCABundlePath | string | `""` | Optional path (inside the container) of a PEM file of root CAs to trust when fetching from federationBundleEndpoints. This chart has no built-in mechanism to mount an extra file into the container, so this is only useful if the image already has the file baked in, or via a separately managed volume/volumeMount layered on with a Helm post-renderer or a chart fork. Empty (default) uses the system trust store, the common case for an endpoint behind a normal ALB/ingress with a publicly trusted certificate, which needs nothing set here. |
| spire.localTrustDomain | string | `""` | The agent's OWN trust domain. When a caller lives in the same trust domain as this agent, list that domain in trustDomains (so it's accepted) AND set it here, so the federated ClusterSPIFFEID excludes it from federatesWith (SPIRE cannot federate a trust domain with itself). Leave empty when every caller is remote. This lets you trust a LOCAL caller and REMOTE callers at the same time, without disabling federation entirely (skipFederation). Example: "rpi.loafoe.com" |
| spire.mtlsEnabled | bool | `false` | Enable X.509 mTLS (requires direct pod-to-pod communication). When false, only JWT-SVID authentication is used (works behind gateways) |
| spire.skipFederation | bool | `false` | Skip creating the federated ClusterSPIFFEID (use when ALL callers are in the same trust domain as this agent — federation with self is invalid) |
| spire.socketMountPath | string | `"/spiffe-workload-api"` | Mount path for the SPIRE socket inside the container |
| spire.trustDomain | string | `""` | Legacy single trust domain (use trustDomains for new deployments). Kept for backward compatibility |
| spire.trustDomains | list | `[]` | Trust domains to accept (supports federation with multiple domains). Example: ["example.org", "partner.com"] |
| tolerations | list | `[]` | Tolerations for pod scheduling |
| vpa.enabled | bool | `true` | Enable creation of a VerticalPodAutoscaler resource (requires the VPA CRDs) |
| vpa.inPlaceResize | bool | `false` | Enable in-place resize (requires K8s 1.27+ with InPlacePodVerticalScaling feature gate) |
| vpa.maxAllowed | object | `{"cpu":"500m","memory":"1Gi"}` | Upper bound on resources the VPA will recommend |
| vpa.minAllowed | object | `{"cpu":"5m","memory":"16Mi"}` | Lower bound on resources the VPA will recommend |
| vpa.minReplicas | int | `1` | Minimum replicas the VPA will allow while resizing |
| vpa.updateMode | string | `"InPlaceOrRecreate"` | VPA update mode (e.g. Off, Initial, Auto, InPlaceOrRecreate) |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
