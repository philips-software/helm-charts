# Onboarding a New Cluster

This guide walks you through deploying pico-agent to a new Kubernetes cluster and connecting it to pico-mcp.

## Quick install (one-liner)

For clusters that already have SPIRE installed and follow the common conventions
(a SPIRE controller class, a Gateway API `Gateway`, and a consistent hostname
pattern), the whole flow below is automated by [`install.sh`](install.sh):

```bash
curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/pico-agent/install.sh | bash
```

It targets your **current `kubectl` context**, auto-discovers the SPIRE class
name, Gateway, base domain and cluster name, applies the pico-mcp
`ClusterFederatedTrustDomain`, and runs `helm upgrade --install`. It is
non-interactive and fails fast if `kubectl`/`helm` are missing or the cluster is
unreachable.

The HTTPRoute is **always created without a `sectionName`** (it attaches to all
listeners and relies on hostname precedence) — setting a specific listener
causes redirect loops on gateways with an all-listener `http-to-https-redirect`
route. The installer also strips any leftover `sectionName` from a
previously-created route. If you have a setup that genuinely needs one, pass
`GATEWAY_SECTION=<listener>` explicitly (discouraged).

**Preview without changing anything:**

```bash
curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/pico-agent/install.sh | DRY_RUN=true bash
```

**Override any auto-discovered or baked-in value via env vars** (see the clearly
delimited `BAKED-IN DEFAULTS` block at the top of the script). The pico-mcp
federation settings (trust domain, bundle endpoint, allowed SPIFFE ID) are baked
in there and easy to edit; everything else is discovered or overridable:

```bash
# Onboard a different pico-mcp, custom hostname, pinned chart:
curl -fsSL .../install.sh | \
  MCP_TRUST_DOMAIN=other.example.com \
  HOSTNAME_FQDN=pico-agent.edge.example.com \
  CHART_VERSION=0.43.0 bash
```

**Read-only mode.** For an observe-only agent, set `READ_ONLY=true`. This
disables every mutating task — `workloadRestart`, `workloadScale`, `podEvict`,
`podResize`, `nodeclaimDelete`, `pvResize`, `autoRemediate` — while keeping all
introspection tasks enabled (`getResource`, `argocd`, `configmapRead`,
`httpRequest`). The mutating flags are set to `false` explicitly, so re-running
also disables them on an existing install.

```bash
curl -fsSL .../install.sh | READ_ONLY=true bash
```

**nginx Ingress fallback.** Some clusters have a broken gateway
`http-to-https-redirect` that causes redirect loops even with no `sectionName`.
For those, set `USE_INGRESS=true` to expose pico-agent via an nginx Ingress
instead of a Gateway API HTTPRoute. The installer disables the HTTPRoute,
auto-discovers the `IngressClass` (prefers `nginx`) and a cert-manager
`ClusterIssuer` (prefers one named `*prod*`), and applies the Ingress. It
**fails fast if the cluster has no ingress controller** (no `IngressClass`) —
no workarounds. Override discovery with `INGRESS_CLASS=`, `CLUSTER_ISSUER=`,
`INGRESS_TLS_SECRET=`.

```bash
curl -fsSL .../install.sh | USE_INGRESS=true bash
```

If your cluster doesn't fit these conventions, follow the manual steps below.

### Uninstall

To remove pico-agent from the current cluster, use [`uninstall.sh`](uninstall.sh).
It requires a **hard confirmation** — you must type the agent id (the
kube-context / cluster name) exactly before anything is deleted:

```bash
curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/pico-agent/uninstall.sh | bash
```

It removes the Helm release and namespace but **keeps** the SPIRE
`ClusterFederatedTrustDomain` (often shared). Pass `REMOVE_FEDERATION=true` to
delete that too, or `DRY_RUN=true` to preview. Remember to deregister the agent
in pico-mcp afterwards.

## Prerequisites

- Kubernetes cluster with SPIRE installed (with controller/CRDs)
- Helm 3.x installed
- kubectl access to the target cluster
- pico-mcp deployed with SPIFFE/SPIRE authentication

## Step 1: Configure SPIRE Federation

The target cluster's SPIRE server must trust the pico-mcp cluster before pico-agent can validate incoming requests.

### Check for SPIRE CRDs

```bash
kubectl --context <your-context> get crd | grep spire
```

If you see `clusterfederatedtrustdomains.spire.spiffe.io`, use the CRD method below.

### Create ClusterFederatedTrustDomain

```bash
cat <<'EOF' | kubectl --context <your-context> apply -f -
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterFederatedTrustDomain
metadata:
  name: <pico-mcp-cluster-name>
spec:
  trustDomain: <pico-mcp-trust-domain>
  bundleEndpointURL: <pico-mcp-bundle-endpoint>
  bundleEndpointProfile:
    type: https_web
  className: <your-spire-class-name>
EOF
```

**Important**: The `className` must match your SPIRE controller's class. Check existing resources:

```bash
kubectl --context <your-context> get clusterspiffeids -o yaml | grep className
```

### Verify federation

Check the SPIRE controller manager logs for successful bundle fetch:

```bash
kubectl --context <your-context> logs -n spire-server <spire-server-pod> -c spire-controller-manager --tail=20 | grep -i "federation\|bundle"
```

You should see: `Created federation relationship`

## Step 2: Create pico-agent values file

Create `values-<cluster-name>.yaml`:

```yaml
image:
  tag: v0.32.0  # pico-agent version

spire:
  # SPIRE is enabled by default
  csi:
    enabled: true

  # Trust the pico-mcp cluster
  trustDomains:
    - <pico-mcp-trust-domain>

  # Allow calls from pico-mcp service account
  allowedSPIFFEIDs:
    - spiffe://<pico-mcp-trust-domain>/ns/<pico-mcp-namespace>/sa/<pico-mcp-service-account>

  # JWT audience - must be unique per agent
  jwt:
    enabled: true
    audiences:
      - pico-agent-<cluster-name>

# Expose via Gateway API (adjust for your cluster)
httpRoute:
  enabled: true
  hostname: pico-agent.<your-domain>
  gatewayRef:
    name: <gateway-name>
    namespace: <gateway-namespace>
    sectionName: ""  # Empty string to attach to all listeners - avoids redirect loops
```

**Important**: Use `sectionName: ""` (empty string) rather than specifying a specific listener like `https-0`. This avoids redirect loops caused by misconfigured `http-to-https-redirect` HTTPRoutes that attach to all listeners. The more specific hostname in pico-agent's HTTPRoute takes precedence over wildcard redirect routes.

### Finding your cluster's domain pattern

```bash
kubectl --context <your-context> get httproutes -A
```

Look at existing hostnames to determine the domain pattern.

### Finding your gateway

```bash
kubectl --context <your-context> get gateways -A
```

## Step 3: Deploy pico-agent

The chart is published both as an OCI artifact and via the classic Helm repo.

```bash
# Option A — OCI (no `helm repo add` needed)
helm upgrade --install pico-agent oci://ghcr.io/philips-software/helm-charts/pico-agent \
  -n pico-agent --create-namespace \
  --kube-context <your-context> \
  -f values-<cluster-name>.yaml

# Option B — classic Helm repo
helm repo add philips-software https://philips-software.github.io/helm-charts/
helm repo update
helm upgrade --install pico-agent philips-software/pico-agent \
  -n pico-agent --create-namespace \
  --kube-context <your-context> \
  -f values-<cluster-name>.yaml
```

### Verify pod is healthy

```bash
kubectl --context <your-context> get pods -n pico-agent -w
```

Wait for `1/1 Running`. If the pod keeps restarting, check if federation is working (Step 1).

### Check logs for successful SPIFFE identity

```bash
kubectl --context <your-context> logs -n pico-agent deploy/pico-agent --tail=20
```

Look for:
```
acquired SPIFFE identity
JWT-SVID validation enabled
starting main server
```

## Step 4: Register agent in pico-mcp

Add the new agent to your pico-mcp configuration:

```yaml
agents:
  # ... existing agents ...
  - id: <cluster-name>
    url: https://pico-agent.<your-domain>
    jwt_audience: pico-agent-<cluster-name>  # Must match Step 2
```

Deploy the updated pico-mcp configuration.

## Step 5: Verify connectivity

Test via pico-mcp:

```
list pico agents
```

You should see `<cluster-name>` in the list. Then test:

```
what is the cluster info for <cluster-name>?
```

## Troubleshooting

### Pod stuck in CrashLoopBackOff

Usually means federation isn't working. Check SPIRE controller logs:

```bash
kubectl --context <your-context> logs -n spire-server <spire-server-pod> -c spire-controller-manager --tail=50 | grep -i error
```

Common error: `unable to find federated bundle` - means the `ClusterFederatedTrustDomain` is missing `className` or bundle endpoint is unreachable.

### Check ClusterSPIFFEID status

```bash
kubectl --context <your-context> get clusterspiffeids pico-agent-federated -o yaml
```

Look at `status.stats.entryFailures` - should be 0.

### Check pico-agent logs

```bash
kubectl --context <your-context> logs -n pico-agent deploy/pico-agent -f
```

### Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Pod restarts, hangs after "connecting to SPIRE" | Federation not configured | Add `ClusterFederatedTrustDomain` with correct `className` |
| `entryFailures: 1` in ClusterSPIFFEID | Bundle not fetched | Check `className` matches SPIRE controller |
| `unable to find federated bundle` | Federation CRD missing className | Add `className` to ClusterFederatedTrustDomain |
| Empty response from pico-agent URL | Expected - requires SPIFFE JWT | Test via pico-mcp, not curl |
| `401 Unauthorized` | JWT audience mismatch | Verify `jwt_audience` in pico-mcp matches `jwt.audiences` in pico-agent |
| Redirect loop on HTTPS URL | Platform's `http-to-https-redirect` HTTPRoute attaches to all listeners | Use `sectionName: ""` (empty) to let hostname precedence work, or use nginx Ingress as fallback |
| `NotAllowedByListeners` in HTTPRoute status | Namespace restrictions on listener | Use `sectionName: ""` to attach to `https-0` which allows all namespaces |
| Redirect loop persists after HTTPRoute fix | Gateway has broken http-to-https-redirect | First try `sectionName: ""`, if still failing use nginx Ingress (see Alternative section below) |
| `UPGRADE FAILED: … exists and cannot be imported … missing key "app.kubernetes.io/managed-by"` | A chart resource (e.g. the HTTPRoute) was created outside Helm and lacks Helm ownership metadata | `install.sh` adopts such resources automatically (stamps the Helm label/annotations before upgrading). Disable with `ADOPT_RESOURCES=false`. To fix by hand: `kubectl -n pico-agent annotate <kind>/pico-agent meta.helm.sh/release-name=pico-agent meta.helm.sh/release-namespace=pico-agent --overwrite && kubectl -n pico-agent label <kind>/pico-agent app.kubernetes.io/managed-by=Helm --overwrite` |

## Alternative: Using nginx Ingress Instead of Gateway API

Some clusters have misconfigured gateway http-to-https redirect routes that cause redirect loops. If you can't fix the gateway configuration, use nginx Ingress instead:

1. Disable HTTPRoute in values.yaml:
```yaml
httpRoute:
  enabled: false
```

2. Create nginx Ingress manually:
```bash
cat <<'EOF' | kubectl --context <your-context> apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pico-agent
  namespace: pico-agent
  annotations:
    cert-manager.io/cluster-issuer: <your-cluster-issuer>
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - pico-agent.<your-domain>
    secretName: pico-agent-tls
  rules:
  - host: pico-agent.<your-domain>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pico-agent
            port:
              number: 8080
EOF
```

3. Wait for external-dns to create the DNS record (check with `dig pico-agent.<your-domain>`)

4. Verify TLS certificate is issued:
```bash
kubectl --context <your-context> get certificate -n pico-agent
```

## Why `sectionName: ""`?

Many clusters have an `http-to-https-redirect` HTTPRoute that redirects HTTP to HTTPS. If this route doesn't specify a `sectionName`, it attaches to ALL gateway listeners including the HTTPS listener. After TLS termination, the backend traffic appears as HTTP, triggering the redirect again and causing an infinite loop.

By omitting `sectionName` (using empty string), pico-agent's HTTPRoute also attaches to all listeners. The Gateway API hostname precedence rules ensure that the specific hostname takes priority over wildcards, so pico-agent's route handles the traffic instead of the redirect route.

To diagnose redirect loop issues, check if the platform's redirect route is missing `sectionName`:

```bash
kubectl --context <your-context> get httproute http-to-https-redirect -n kube-system -o yaml | grep -A5 parentRefs
```

If you see no `sectionName` field, that's the root cause. The proper fix is for the platform team to add `sectionName: http-0` to constrain it to the HTTP listener only.
