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
: "${HTTPROUTE_ENABLED:=true}"
: "${GATEWAY_NAME:=}"         # auto: a Gateway literally named "gateway", else first
: "${GATEWAY_NAMESPACE:=}"    # auto: namespace of the chosen Gateway
: "${GATEWAY_SECTION:=}"      # auto: an https listener, else "" (all listeners)
: "${HOSTNAME_FQDN:=}"        # auto: pico-agent.<base-domain>
: "${BASE_DOMAIN:=}"          # auto: most common HTTPRoute hostname suffix

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
# ============================================================================
# END CONFIG
# ============================================================================

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

    # Section: an HTTPS listener literally named "https", else "" (all listeners)
    if [ -z "$GATEWAY_SECTION" ]; then
      GATEWAY_SECTION=$(kubectl -n "$GATEWAY_NAMESPACE" get gateway "$GATEWAY_NAME" \
        -o jsonpath='{range .spec.listeners[?(@.protocol=="HTTPS")]}{.name}{"\n"}{end}' 2>/dev/null \
        | awk '$0=="https"{print;exit}')
      # else leave empty -> attach to all listeners (hostname precedence wins)
    fi

    # Base domain: most common HTTPRoute hostname suffix (strip first label)
    if [ -z "$HOSTNAME_FQDN" ]; then
      if [ -z "$BASE_DOMAIN" ]; then
        BASE_DOMAIN=$(kubectl get httproutes -A \
          -o jsonpath='{range .items[*]}{range .spec.hostnames[*]}{@}{"\n"}{end}{end}' 2>/dev/null \
          | sed 's/^[^.]*\.//' | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
      fi
      [ -n "$BASE_DOMAIN" ] || die "could not discover base domain; set BASE_DOMAIN=... or HOSTNAME_FQDN=..."
      HOSTNAME_FQDN="pico-agent.${BASE_DOMAIN}"
    fi
  fi
}

# ---------------------------------------------------------------------------
# summarize: show the resolved plan (no secrets), as an elegant panel
# ---------------------------------------------------------------------------
summarize() {
  local route="disabled"
  [ "$HTTPROUTE_ENABLED" = "true" ] && \
    route="$(printf '%s  (gw %s/%s, section "%s")' "$HOSTNAME_FQDN" "$GATEWAY_NAMESPACE" "$GATEWAY_NAME" "$GATEWAY_SECTION")"

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
  _row "🛣️ " "httproute"    "${route}"
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
# deploy: helm upgrade --install with resolved values
# ---------------------------------------------------------------------------
deploy() {
  local -a args=(
    upgrade --install "$RELEASE_NAME" "$CHART"
    --namespace "$NAMESPACE" --create-namespace
    --set "replicaCount=${REPLICA_COUNT}"
    --set "spire.csi.enabled=true"
    --set "spire.className=${SPIRE_CLASSNAME}"
    --set "spire.trustDomains[0]=${MCP_TRUST_DOMAIN}"
    --set "spire.allowedSPIFFEIDs[0]=${MCP_SPIFFE_ID}"
    --set "spire.jwt.enabled=true"
    --set "spire.jwt.audiences[0]=${JWT_AUDIENCE}"
    --set "serviceMonitor.enabled=${SERVICEMONITOR_ENABLED}"
  )

  [ -n "$CHART_VERSION" ] && args+=( --version "$CHART_VERSION" )
  [ -n "$IMAGE_TAG" ]     && args+=( --set "image.tag=${IMAGE_TAG}" )

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
      --set "httpRoute.gatewayRef.sectionName=${GATEWAY_SECTION}"
    )
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

mcp_pico-mcp_upsert_agent(
  id: "${CLUSTER_NAME}",
  url: "${url}",
  jwt_audience: "${JWT_AUDIENCE}"
)
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
  deploy
  verify
  done_msg
}

main "$@"
