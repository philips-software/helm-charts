#!/usr/bin/env bash
#
# pico-agent one-liner installer
#
#   curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/pico-agent/install.sh | bash
#
# Deploys pico-agent to the *current* kubectl cluster and wires it up to pico-mcp
# via SPIRE federation. It auto-discovers everything it can from the target
# cluster (SPIRE class name, Gateway, base domain, cluster name) and falls back
# to the baked-in defaults below. Nothing is prompted; it fails fast instead.
#
# Override any discovered/baked-in value by exporting the matching env var, e.g.
#
#   CLUSTER_NAME=edge BASE_DOMAIN=example.com \
#     curl -fsSL .../install.sh | bash
#
# For an observe-only agent (all mutating tasks disabled), set READ_ONLY=true:
#
#   curl -fsSL .../install.sh | READ_ONLY=true bash
#
# To expose via an nginx Ingress instead of a Gateway API HTTPRoute (for
# clusters whose gateway has a broken http-to-https redirect), USE_INGRESS=true.
# Requires an ingress controller — it fails fast if no IngressClass exists:
#
#   curl -fsSL .../install.sh | USE_INGRESS=true bash
#
set -euo pipefail

# ============================================================================
# BAKED-IN DEFAULTS  --  edit these, or override per-run with env vars
# ============================================================================
# pico-mcp federation settings. These describe the *caller* (pico-mcp) cluster
# that pico-agent must trust. They are stable across target clusters, so they
# are baked in here. Override with env vars if you onboard a different pico-mcp.
: "${MCP_TRUST_DOMAIN:=dip-ce-k3s-eu.hsp.philips.com}"
: "${MCP_BUNDLE_ENDPOINT:=https://spiffe.dip-ce-k3s-eu.hsp.philips.com}"
: "${MCP_SPIFFE_ID:=spiffe://dip-ce-k3s-eu.hsp.philips.com/ns/pico-mcp/sa/pico-mcp}"
: "${MCP_FEDERATION_NAME:=dip-ce-k3s-eu}"   # name of the ClusterFederatedTrustDomain

# Install target
: "${NAMESPACE:=pico-agent}"
: "${RELEASE_NAME:=pico-agent}"
: "${CHART:=oci://ghcr.io/philips-software/helm-charts/pico-agent}"
: "${CHART_VERSION:=}"        # empty = latest
: "${IMAGE_TAG:=}"            # empty = chart default appVersion

# Read-only mode: disable every mutating task, keep all introspection/read
# tasks enabled. Set READ_ONLY=true for an observe-only agent.
: "${READ_ONLY:=false}"

# Feature flags (helm --set features.*). Edit to taste. An explicit FEATURES
# always wins; otherwise the default is chosen by READ_ONLY. In read-only mode
# the mutating features are explicitly set to false so a re-run also *disables*
# them on an existing install (declarative reconcile).
if [ "$READ_ONLY" = "true" ]; then
  : "${FEATURES:=getResource=true,argocd=true,configmapRead=true,httpRequest=true,workloadRestart=false,workloadScale=false,podEvict=false,podResize=false,nodeclaimDelete=false,pvResize=false,autoRemediate=false}"
else
  : "${FEATURES:=argocd=true,autoRemediate=true,configmapRead=true,httpRequest=true,podEvict=true,podResize=true,pvResize=true,workloadRestart=true,workloadScale=true}"
fi

# Networking / exposure. Empty values are auto-discovered (see below).
#
# Two mutually exclusive modes:
#   - Gateway API HTTPRoute (default)
#   - nginx Ingress fallback (USE_INGRESS=true) — for clusters whose gateway
#     has a broken http-to-https-redirect that causes loops. The chart has no
#     Ingress template, so the installer applies the Ingress directly (same
#     pattern as the federation CRD) and sets httpRoute.enabled=false.
: "${USE_INGRESS:=false}"
: "${HTTPROUTE_ENABLED:=true}"
: "${GATEWAY_NAME:=}"         # auto: a Gateway literally named "gateway", else first
: "${GATEWAY_NAMESPACE:=}"    # auto: namespace of the chosen Gateway
: "${GATEWAY_SECTION:=}"      # leave EMPTY (default): no sectionName -> attach to
                             # all listeners. Setting a listener causes redirect
                             # loops with all-listener http-to-https-redirect routes.
: "${HOSTNAME_FQDN:=}"        # auto: pico-agent.<base-domain>
: "${BASE_DOMAIN:=}"          # auto: most common HTTPRoute hostname suffix

# nginx Ingress fallback (used only when USE_INGRESS=true)
: "${INGRESS_CLASS:=}"        # auto: an IngressClass named "nginx", else first
: "${CLUSTER_ISSUER:=}"       # auto: a ClusterIssuer named *prod*, else first
: "${INGRESS_TLS_SECRET:=pico-agent-tls}"

# Identity
: "${CLUSTER_NAME:=}"         # auto: current kube-context name
: "${SPIRE_CLASSNAME:=}"      # auto: most common ClusterSPIFFEID className
: "${JWT_AUDIENCE:=}"         # auto: pico-agent-<cluster-name>

# Behaviour
: "${SERVICEMONITOR_ENABLED:=true}"
: "${REPLICA_COUNT:=1}"
: "${DRY_RUN:=false}"         # true = print helm/kubectl actions, change nothing
: "${WAIT_TIMEOUT:=180s}"
: "${COUNTDOWN:=}"            # pre-install review countdown (s); empty = auto from reading time
: "${ASSUME_YES:=false}"     # true = skip the countdown entirely (CI / unattended)
: "${ADOPT_RESOURCES:=true}" # stamp Helm ownership onto pre-existing chart resources
                             # that lack it, so `helm upgrade` can adopt them
# ============================================================================
# END CONFIG
# ============================================================================

# Ingress mode and HTTPRoute mode are mutually exclusive: enabling the nginx
# Ingress fallback disables the chart's Gateway API HTTPRoute.
if [ "$USE_INGRESS" = "true" ]; then
  HTTPROUTE_ENABLED=false
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "true" ]; then printf '\033[2m# %s\033[0m\n' "$*" >&2; else eval "$@"; fi; }

# ---------------------------------------------------------------------------
# preflight: fail fast on missing tools / unreachable cluster
# ---------------------------------------------------------------------------
preflight() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
  command -v helm    >/dev/null 2>&1 || die "helm not found in PATH"

  local hv
  hv=$(helm version --short 2>/dev/null || true)
  case "$hv" in
    v3.*|v4.*) : ;;
    *) die "helm 3.x or newer required (found: ${hv:-unknown})" ;;
  esac

  kubectl version >/dev/null 2>&1 \
    || die "cannot reach a Kubernetes cluster (check your kubeconfig / current-context)"
}

# ---------------------------------------------------------------------------
# discover: fill in any empty config value from the live cluster
# ---------------------------------------------------------------------------
discover() {
  CTX=$(kubectl config current-context 2>/dev/null) || die "no current kube-context"

  [ -n "$CLUSTER_NAME" ] || CLUSTER_NAME="$CTX"
  [ -n "$JWT_AUDIENCE" ] || JWT_AUDIENCE="pico-agent-${CLUSTER_NAME}"

  # Is the release already present? Used purely for messaging (the helm
  # upgrade --install below is idempotent either way).
  RELEASE_EXISTS=false
  helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1 && RELEASE_EXISTS=true

  # SPIRE className: most common across existing ClusterSPIFFEIDs
  if [ -z "$SPIRE_CLASSNAME" ]; then
    SPIRE_CLASSNAME=$(kubectl get clusterspiffeids \
      -o jsonpath='{range .items[*]}{.spec.className}{"\n"}{end}' 2>/dev/null \
      | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  fi
  [ -n "$SPIRE_CLASSNAME" ] || die "could not discover SPIRE className; set SPIRE_CLASSNAME=..."

  if [ "$HTTPROUTE_ENABLED" = "true" ]; then
    # Gateway: prefer one literally named "gateway", else the first one
    if [ -z "$GATEWAY_NAME" ]; then
      local gw
      gw=$(kubectl get gateways -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)
      local pick
      pick=$(printf '%s\n' "$gw" | awk -F/ '$2=="gateway"{print;exit}')
      [ -n "$pick" ] || pick=$(printf '%s\n' "$gw" | grep -v '^$' | head -1)
      [ -n "$pick" ] || die "no Gateway found; set GATEWAY_NAME/GATEWAY_NAMESPACE or HTTPROUTE_ENABLED=false"
      GATEWAY_NAMESPACE="${pick%%/*}"
      GATEWAY_NAME="${pick##*/}"
    fi

    # Section: intentionally NOT auto-discovered. We must NOT set a
    # sectionName — attaching to a specific listener triggers redirect loops
    # in setups whose http-to-https-redirect route also attaches to all
    # listeners. Leaving it empty attaches to all listeners and lets Gateway
    # API hostname precedence route correctly. Only an explicit
    # GATEWAY_SECTION=... env override will set one (discouraged).

    # Base domain: most common HTTPRoute hostname suffix (strip first label)
    if [ -z "$HOSTNAME_FQDN" ]; then
      [ -n "$BASE_DOMAIN" ] || BASE_DOMAIN=$(discover_base_domain httproute)
      [ -n "$BASE_DOMAIN" ] || die "could not discover base domain; set BASE_DOMAIN=... or HOSTNAME_FQDN=..."
      HOSTNAME_FQDN="pico-agent.${BASE_DOMAIN}"
    fi
  fi

  if [ "$USE_INGRESS" = "true" ]; then
    # IngressClass: prefer one literally named "nginx", else the first.
    # If the cluster has no IngressClass at all, fail out — no workarounds.
    if [ -z "$INGRESS_CLASS" ]; then
      local classes
      classes=$(kubectl get ingressclass \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
      INGRESS_CLASS=$(printf '%s\n' "$classes" | awk '$0=="nginx"{print;exit}')
      [ -n "$INGRESS_CLASS" ] || INGRESS_CLASS=$(printf '%s\n' "$classes" | awk 'NF{print;exit}')
    fi
    [ -n "$INGRESS_CLASS" ] || \
      die "USE_INGRESS=true but no IngressClass found in the cluster (no ingress controller). Aborting."

    # ClusterIssuer: prefer one whose name contains "prod", else the first.
    if [ -z "$CLUSTER_ISSUER" ]; then
      local issuers
      issuers=$(kubectl get clusterissuers \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
      CLUSTER_ISSUER=$(printf '%s\n' "$issuers" | awk '/[Pp]rod/{print;exit}')
      [ -n "$CLUSTER_ISSUER" ] || CLUSTER_ISSUER=$(printf '%s\n' "$issuers" | awk 'NF{print;exit}')
      [ -n "$CLUSTER_ISSUER" ] || warn "no ClusterIssuer found; Ingress will have no TLS issuer annotation (set CLUSTER_ISSUER=...)"
    fi

    # Hostname: derive the base domain from existing Ingress hosts first
    # (the cluster may not use Gateway API), then fall back to HTTPRoute hosts.
    if [ -z "$HOSTNAME_FQDN" ]; then
      [ -n "$BASE_DOMAIN" ] || BASE_DOMAIN=$(discover_base_domain ingress)
      [ -n "$BASE_DOMAIN" ] || BASE_DOMAIN=$(discover_base_domain httproute)
      [ -n "$BASE_DOMAIN" ] || die "could not discover base domain; set BASE_DOMAIN=... or HOSTNAME_FQDN=..."
      HOSTNAME_FQDN="pico-agent.${BASE_DOMAIN}"
    fi
  fi
}

# discover_base_domain <ingress|httproute>: most common hostname suffix (the
# part after the first label) across existing routes of that kind. Prints the
# domain or nothing. Pipefail-safe: a filter matching nothing must not abort.
discover_base_domain() {
  local hosts
  if [ "$1" = "ingress" ]; then
    hosts=$(kubectl get ingress -A \
      -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' 2>/dev/null || true)
  else
    hosts=$(kubectl get httproutes -A \
      -o jsonpath='{range .items[*]}{range .spec.hostnames[*]}{@}{"\n"}{end}{end}' 2>/dev/null || true)
  fi
  printf '%s\n' "$hosts" | sed 's/^[^.]*\.//' | awk 'NF' \
    | sort | uniq -c | sort -rn | awk 'NR==1{print $2}'
}

# ---------------------------------------------------------------------------
# summarize: show the resolved plan (no secrets), as an elegant panel
# ---------------------------------------------------------------------------
summarize() {
  printf '\n' >&2
  printf '  \033[1;36m🚀 pico-agent\033[0m \033[2m· resolved install plan\033[0m\n' >&2
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  _row "🎯" "target"       "${CLUSTER_NAME}  \033[2m(context: ${CTX})\033[0m"
  _row "📦" "release"      "${RELEASE_NAME}  →  ns/${NAMESPACE}"
  _row "🏷️ " "chart"        "${CHART##*/}${CHART_VERSION:+ @ ${CHART_VERSION}}  \033[2m(image: ${IMAGE_TAG:-chart default})\033[0m"
  _row "🔐" "spire class"  "${SPIRE_CLASSNAME}"
  _row "🤝" "trusts mcp"   "${MCP_TRUST_DOMAIN}"
  _row "🪪 " "spiffe id"    "${MCP_SPIFFE_ID}"
  _row "🌐" "federation"   "${MCP_FEDERATION_NAME}  →  ${MCP_BUNDLE_ENDPOINT}"
  _row "🎫" "jwt audience" "${JWT_AUDIENCE}"
  if [ "$USE_INGRESS" = "true" ]; then
    _row "🌉" "ingress"     "${HOSTNAME_FQDN}  \033[2m(class ${INGRESS_CLASS}, issuer ${CLUSTER_ISSUER:-none})\033[0m"
  elif [ "$HTTPROUTE_ENABLED" = "true" ]; then
    _row "🛣️ " "httproute"    "$(printf '%s  (gw %s/%s, section: %s)' "$HOSTNAME_FQDN" "$GATEWAY_NAMESPACE" "$GATEWAY_NAME" "${GATEWAY_SECTION:-none (all listeners)}")"
  else
    _row "🛣️ " "route"        "disabled"
  fi
  _row "📊" "monitoring"   "serviceMonitor=${SERVICEMONITOR_ENABLED}"
  if [ "$READ_ONLY" = "true" ]; then
    _row "👁️ " "mode"         "\033[1;33mREAD-ONLY\033[0m \033[2m(mutating tasks disabled; introspection only)\033[0m"
  fi
  if [ "$RELEASE_EXISTS" = "true" ]; then
    _row "♻️ " "action"       "reconcile existing release \033[2m(idempotent — no change if already current)\033[0m"
  else
    _row "🌱" "action"       "fresh install"
  fi
  [ "$DRY_RUN" = "true" ] && _row "🧪" "mode"        "\033[1;33mDRY RUN — nothing will change\033[0m"
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  printf '\n' >&2
}

# _row <emoji> <label> <value>
_row() {
  printf '  %s  \033[1m%-13s\033[0m %b\n' "$1" "$2" "$3" >&2
}

# ---------------------------------------------------------------------------
# confirm_countdown: give the operator time to read the plan; ESC aborts.
# Reads keys from /dev/tty so it works under `curl ... | bash`.
# ---------------------------------------------------------------------------
confirm_countdown() {
  [ "$DRY_RUN" = "true" ] && return 0
  [ "$ASSUME_YES" = "true" ] && { log "ASSUME_YES=true — skipping review countdown"; return 0; }

  # Auto-pick a duration from "reading time". The panel has ~11 rows of
  # short key→value pairs; scanning config (not prose) runs ~1.5s/row. We
  # budget that and clamp to a humane 8–20s window. Override with COUNTDOWN.
  local secs="$COUNTDOWN"
  if [ -z "$secs" ]; then
    local rows=11
    secs=$(( (rows * 3) / 2 ))      # ~1.5s per row
    [ "$secs" -lt 8 ]  && secs=8
    [ "$secs" -gt 20 ] && secs=20
  fi

  # Need a real terminal to capture ESC; if none, fall back to a plain sleep.
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    printf '  \033[2m⏳ starting in %ss (no TTY — cannot abort)\033[0m\n' "$secs" >&2
    sleep "$secs"
    printf '\n' >&2
    return 0
  fi

  local tty=/dev/tty
  [ -r "$tty" ] || tty=/dev/stdin

  printf '  \033[1;32m✨ Review the plan above.\033[0m  Installing in \033[1m%ss\033[0m — press \033[1mESC\033[0m to abort, \033[1mENTER\033[0m to go now.\n' "$secs" >&2

  local remaining="$secs" key
  while [ "$remaining" -gt 0 ]; do
    printf '\r  \033[2m⏳ %2ss …\033[0m \033[2m(ESC = abort)\033[0m   ' "$remaining" >&2
    # read one key with a 1s timeout from the terminal
    if IFS= read -rsn1 -t 1 key <"$tty" 2>/dev/null; then
      case "$key" in
        $'\e')        printf '\r\033[K  \033[1;31m🛑 aborted by operator — nothing changed.\033[0m\n' >&2; exit 130 ;;
        ''|$'\n'|$'\r') printf '\r\033[K  \033[1;32m▶️  proceeding now.\033[0m\n' >&2; return 0 ;;  # ENTER (LF or CR)
        *)            : ;;  # any other key: ignore, keep counting
      esac
    fi
    remaining=$((remaining - 1))
  done
  printf '\r\033[K  \033[1;32m▶️  proceeding.\033[0m\n' >&2
}

# ---------------------------------------------------------------------------
# configure_federation: ensure the ClusterFederatedTrustDomain exists
# ---------------------------------------------------------------------------
configure_federation() {
  if ! kubectl get crd clusterfederatedtrustdomains.spire.spiffe.io >/dev/null 2>&1; then
    die "SPIRE CRD clusterfederatedtrustdomains.spire.spiffe.io not found — is SPIRE installed?"
  fi

  # Guard: skip if installing on the same cluster as pico-mcp (self-federation
  # breaks SPIRE agents — they cannot fetch a federated bundle for their own trust domain)
  if [ "$CLUSTER_NAME" = "$MCP_FEDERATION_NAME" ]; then
    log "skipping federation — installing on pico-mcp's own cluster '${CLUSTER_NAME}' (cannot federate with self)"
    _SKIP_FEDERATION=true
    return 0
  fi

  log "applying ClusterFederatedTrustDomain '${MCP_FEDERATION_NAME}'"
  local manifest
  manifest=$(cat <<EOF
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterFederatedTrustDomain
metadata:
  name: ${MCP_FEDERATION_NAME}
spec:
  trustDomain: ${MCP_TRUST_DOMAIN}
  bundleEndpointURL: ${MCP_BUNDLE_ENDPOINT}
  bundleEndpointProfile:
    type: https_web
  className: ${SPIRE_CLASSNAME}
EOF
)
  if [ "$DRY_RUN" = "true" ]; then
    printf '\033[2m# kubectl apply -f - <<EOF\n%s\nEOF\033[0m\n' "$manifest" >&2
  else
    printf '%s\n' "$manifest" | kubectl apply -f - >&2 \
      || die "failed to apply ClusterFederatedTrustDomain"
  fi
}

# ---------------------------------------------------------------------------
# configure_ingress: nginx Ingress fallback (USE_INGRESS=true). The chart has
# no Ingress template, so we apply one directly — mirroring the manual recipe
# in ONBOARD.md. Runs AFTER helm (the namespace + Service must exist first).
# Idempotent (kubectl apply). The matching HTTPRoute is disabled via
# httpRoute.enabled=false in deploy().
# ---------------------------------------------------------------------------
configure_ingress() {
  [ "$USE_INGRESS" = "true" ] || return 0

  local issuer_ann=""
  [ -n "$CLUSTER_ISSUER" ] && \
    issuer_ann="    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}"

  log "applying nginx Ingress for ${HOSTNAME_FQDN}"
  local manifest
  manifest=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${RELEASE_NAME}
  namespace: ${NAMESPACE}
  annotations:
${issuer_ann}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: ${INGRESS_CLASS}
  tls:
  - hosts:
    - ${HOSTNAME_FQDN}
    secretName: ${INGRESS_TLS_SECRET}
  rules:
  - host: ${HOSTNAME_FQDN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${RELEASE_NAME}
            port:
              number: 8080
EOF
)
  # drop the empty issuer line if no issuer was resolved
  manifest=$(printf '%s\n' "$manifest" | grep -v '^$')

  if [ "$DRY_RUN" = "true" ]; then
    printf '\033[2m# kubectl apply -f - <<EOF\n%s\nEOF\033[0m\n' "$manifest" >&2
  else
    printf '%s\n' "$manifest" | kubectl apply -f - >&2 \
      || die "failed to apply nginx Ingress"
  fi
}

# ---------------------------------------------------------------------------
# adopt_orphans: let `helm upgrade` take over chart resources that already
# exist but were NOT created by this Helm release (e.g. applied by hand or by
# a previous tool). Helm refuses to overwrite such objects unless they carry
# its ownership metadata:
#   label       app.kubernetes.io/managed-by = Helm
#   annotation  meta.helm.sh/release-name      = <release>
#   annotation  meta.helm.sh/release-namespace = <namespace>
# We stamp exactly those on any pre-existing, un-owned chart resource. This is
# the same metadata Helm would set itself, so adoption is safe and idempotent.
# ---------------------------------------------------------------------------
adopt_orphans() {
  [ "$ADOPT_RESOURCES" = "true" ] || return 0

  local fullname="$RELEASE_NAME"     # chart fullname == release name here
  # kind/name pairs the chart renders into this namespace.
  local -a targets=(
    "httproute.gateway.networking.k8s.io/${fullname}"
    "service/${fullname}"
    "serviceaccount/${fullname}"
    "servicemonitor.monitoring.coreos.com/${fullname}"
    "deployment.apps/${fullname}"
    "verticalpodautoscaler.autoscaling.k8s.io/${fullname}-vpa"
  )

  local res kind name owner adopted=0
  for res in "${targets[@]}"; do
    # exists?
    kubectl -n "$NAMESPACE" get "$res" >/dev/null 2>&1 || continue
    # already Helm-owned by THIS release? then skip.
    owner=$(kubectl -n "$NAMESPACE" get "$res" \
      -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)
    if [ "$owner" = "$RELEASE_NAME" ]; then
      continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
      printf '\033[2m# would adopt %s (label managed-by=Helm + release annotations)\033[0m\n' "$res" >&2
      adopted=$((adopted + 1))
      continue
    fi

    kubectl -n "$NAMESPACE" annotate --overwrite "$res" \
      "meta.helm.sh/release-name=${RELEASE_NAME}" \
      "meta.helm.sh/release-namespace=${NAMESPACE}" >/dev/null 2>&1 || true
    kubectl -n "$NAMESPACE" label --overwrite "$res" \
      "app.kubernetes.io/managed-by=Helm" >/dev/null 2>&1 || true
    log "adopted pre-existing $res into release '$RELEASE_NAME'"
    adopted=$((adopted + 1))
  done

  [ "$adopted" -gt 0 ] || true
}

# ---------------------------------------------------------------------------
# deploy: helm upgrade --install with resolved values
# ---------------------------------------------------------------------------
deploy() {
  local -a args=(
    upgrade --install "$RELEASE_NAME" "$CHART"
    --namespace "$NAMESPACE" --create-namespace
    --set "replicaCount=${REPLICA_COUNT}"
    --set "spire.csi.enabled=true"
    --set "spire.className=${SPIRE_CLASSNAME}"
    --set "spire.allowedSPIFFEIDs[0]=${MCP_SPIFFE_ID}"
    --set "spire.jwt.enabled=true"
    --set "spire.jwt.audiences[0]=${JWT_AUDIENCE}"
    --set "serviceMonitor.enabled=${SERVICEMONITOR_ENABLED}"
  )

  [ -n "$CHART_VERSION" ] && args+=( --version "$CHART_VERSION" )
  [ -n "$IMAGE_TAG" ]     && args+=( --set "image.tag=${IMAGE_TAG}" )

  # Always set trustDomains (needed for JWT caller validation), but skip
  # federation ClusterSPIFFEID when installing on the same cluster as pico-mcp
  args+=( --set "spire.trustDomains[0]=${MCP_TRUST_DOMAIN}" )
  if [ "${_SKIP_FEDERATION:-}" = "true" ]; then
    args+=( --set "spire.skipFederation=true" )
  fi

  # Feature flags
  local IFS=','
  local f
  for f in $FEATURES; do
    [ -n "$f" ] && args+=( --set "features.${f}" )
  done
  unset IFS

  # HTTPRoute exposure
  if [ "$HTTPROUTE_ENABLED" = "true" ]; then
    args+=(
      --set "httpRoute.enabled=true"
      --set "httpRoute.hostname=${HOSTNAME_FQDN}"
      --set "httpRoute.gatewayRef.name=${GATEWAY_NAME}"
      --set "httpRoute.gatewayRef.namespace=${GATEWAY_NAMESPACE}"
    )
    # Only set sectionName if explicitly requested. By default we leave it
    # UNSET so the route attaches to all listeners — setting it to a specific
    # listener causes redirect loops in setups with an all-listener
    # http-to-https-redirect route. Pass empty string to actively clear any
    # value Helm might otherwise carry over.
    args+=( --set "httpRoute.gatewayRef.sectionName=${GATEWAY_SECTION}" )
  else
    args+=( --set "httpRoute.enabled=false" )
  fi

  args+=( --wait --timeout "$WAIT_TIMEOUT" )

  log "running helm upgrade --install"
  if [ "$DRY_RUN" = "true" ]; then
    printf '\033[2m# helm %s\033[0m\n' "${args[*]}" >&2
  else
    helm "${args[@]}" >&2 || die "helm install failed"
  fi
}

# ---------------------------------------------------------------------------
# normalize_route: force the HTTPRoute's parentRef to the exact desired value.
# Helm's 3-way merge will NOT remove a sectionName that a previously-adopted
# (hand-created) route carried, because the chart template simply omits the
# field rather than setting it empty. A leftover sectionName re-introduces the
# redirect-loop risk, so we explicitly rewrite parentRefs here. With an empty
# GATEWAY_SECTION (the default) the result has NO sectionName.
# ---------------------------------------------------------------------------
normalize_route() {
  [ "$HTTPROUTE_ENABLED" = "true" ] || return 0
  [ "$DRY_RUN" = "true" ] && return 0

  local parentref
  if [ -n "$GATEWAY_SECTION" ]; then
    parentref=$(printf '{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"%s","namespace":"%s","sectionName":"%s"}' \
      "$GATEWAY_NAME" "$GATEWAY_NAMESPACE" "$GATEWAY_SECTION")
  else
    parentref=$(printf '{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"%s","namespace":"%s"}' \
      "$GATEWAY_NAME" "$GATEWAY_NAMESPACE")
  fi

  # Only patch if the live parentRefs differ from desired (keeps it a noop).
  local current
  current=$(kubectl -n "$NAMESPACE" get "httproute/${RELEASE_NAME}" \
    -o jsonpath='{.spec.parentRefs[0].sectionName}' 2>/dev/null || true)
  if [ -z "$GATEWAY_SECTION" ] && [ -z "$current" ]; then
    return 0   # already has no sectionName
  fi
  if [ -n "$GATEWAY_SECTION" ] && [ "$current" = "$GATEWAY_SECTION" ]; then
    return 0
  fi

  log "normalizing HTTPRoute parentRef (sectionName: ${GATEWAY_SECTION:-<unset>})"
  kubectl -n "$NAMESPACE" patch "httproute/${RELEASE_NAME}" --type=merge \
    -p "{\"spec\":{\"parentRefs\":[${parentref}]}}" >/dev/null 2>&1 \
    || warn "could not normalize HTTPRoute parentRef (check it manually)"
}

# ---------------------------------------------------------------------------
# verify: confirm the rollout
# ---------------------------------------------------------------------------
verify() {
  [ "$DRY_RUN" = "true" ] && return 0
  log "waiting for deployment rollout"
  kubectl -n "$NAMESPACE" rollout status deploy/"$RELEASE_NAME" --timeout="$WAIT_TIMEOUT" >&2 \
    || warn "rollout did not complete cleanly — check: kubectl -n $NAMESPACE logs deploy/$RELEASE_NAME"
}

# ---------------------------------------------------------------------------
done_msg() {
  local url="https://${HOSTNAME_FQDN:-<your-hostname>}"

  printf '\n' >&2
  if [ "${RELEASE_EXISTS:-false}" = "true" ]; then
    printf '  \033[1;32m✅ pico-agent up to date on \033[1;36m%s\033[1;32m \033[2m(reconciled)\033[0m\n' "$CLUSTER_NAME" >&2
  else
    printf '  \033[1;32m✅ pico-agent installed on \033[1;36m%s\033[1;32m!\033[0m\n' "$CLUSTER_NAME" >&2
  fi
  printf '\n' >&2
  printf '  \033[1m🤖 Register the agent — paste this to ClusterClaw:\033[0m\n' >&2
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  # The ClusterClaw-ready prompt. Goes to stdout (clean, copy/paste friendly).
  cat <<EOF
Please onboard this pico-agent by calling:

mcp_pico-mcp_upsert_agent(url: "${url}")

The agent's /info endpoint will auto-discover id and jwt_audience.
EOF
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  printf '\n' >&2
  printf '  \033[2m🔎 Inspect:\033[0m\n' >&2
  printf '     kubectl -n %s get pods\n' "$NAMESPACE" >&2
  printf '     kubectl -n %s logs deploy/%s --tail=20\n' "$NAMESPACE" "$RELEASE_NAME" >&2
  printf '\n' >&2
}

main() {
  preflight
  discover
  summarize
  confirm_countdown
  configure_federation
  adopt_orphans
  deploy
  normalize_route
  configure_ingress
  verify
  done_msg
}

main "$@"
