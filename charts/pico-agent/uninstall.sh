#!/usr/bin/env bash
#
# pico-agent uninstaller
#
#   curl -fsSL https://raw.githubusercontent.com/philips-software/helm-charts/main/charts/pico-agent/uninstall.sh | bash
#
# Removes pico-agent from the *current* kubectl cluster. Requires a hard
# confirmation: the operator must type the agent id (the cluster/context name)
# exactly before anything is deleted.
#
# By default it removes the Helm release and the namespace, but KEEPS the SPIRE
# ClusterFederatedTrustDomain (federation is often shared). Set
# REMOVE_FEDERATION=true to delete it too.
#
set -euo pipefail

# ----------------------------- config (env-overridable) ---------------------
: "${NAMESPACE:=pico-agent}"
: "${RELEASE_NAME:=pico-agent}"
: "${CLUSTER_NAME:=}"               # agent id; auto = current kube-context
: "${MCP_FEDERATION_NAME:=dip-ce-k3s-eu}"   # CFTD name (only used if removing)
: "${REMOVE_NAMESPACE:=true}"       # delete the namespace after the release
: "${REMOVE_FEDERATION:=false}"     # delete the ClusterFederatedTrustDomain
: "${ASSUME_YES:=false}"            # skip the typed confirmation (CI/danger)
: "${DRY_RUN:=false}"               # print actions, change nothing
: "${WAIT_TIMEOUT:=120s}"
# ----------------------------------------------------------------------------

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

preflight() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
  command -v helm    >/dev/null 2>&1 || die "helm not found in PATH"
  kubectl version >/dev/null 2>&1 \
    || die "cannot reach a Kubernetes cluster (check your kubeconfig / current-context)"
}

discover() {
  CTX=$(kubectl config current-context 2>/dev/null) || die "no current kube-context"
  [ -n "$CLUSTER_NAME" ] || CLUSTER_NAME="$CTX"

  RELEASE_FOUND=false
  helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1 && RELEASE_FOUND=true
}

summarize() {
  printf '\n' >&2
  printf '  \033[1;31m🗑️  pico-agent uninstall\033[0m \033[2m· about to remove\033[0m\n' >&2
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  printf '  \033[1m%-16s\033[0m %s\n' "context"      "$CTX" >&2
  printf '  \033[1m%-16s\033[0m %s\n' "agent id"     "$CLUSTER_NAME" >&2
  printf '  \033[1m%-16s\033[0m %s\n' "helm release" "$RELEASE_NAME (ns/$NAMESPACE)$( [ "$RELEASE_FOUND" = true ] || printf ' \033[2m[not found]\033[0m' )" >&2
  printf '  \033[1m%-16s\033[0m %s\n' "namespace"    "$( [ "$REMOVE_NAMESPACE" = true ] && echo "DELETE ns/$NAMESPACE" || echo "keep" )" >&2
  printf '  \033[1m%-16s\033[0m %s\n' "federation"   "$( [ "$REMOVE_FEDERATION" = true ] && echo "DELETE CFTD/$MCP_FEDERATION_NAME" || echo "keep (shared)" )" >&2
  [ "$DRY_RUN" = true ] && printf '  \033[1m%-16s\033[0m \033[1;33m%s\033[0m\n' "mode" "DRY RUN — nothing will change" >&2
  printf '  \033[2m────────────────────────────────────────────────────────────\033[0m\n' >&2
  printf '\n' >&2
}

# Hard confirm: operator must type the agent id exactly.
confirm() {
  [ "$DRY_RUN" = true ] && return 0
  if [ "$ASSUME_YES" = true ]; then
    warn "ASSUME_YES=true — skipping typed confirmation"
    return 0
  fi

  local tty=/dev/tty
  if [ ! -r "$tty" ]; then
    [ -t 0 ] && tty=/dev/stdin || die "no terminal available for confirmation; set ASSUME_YES=true to force (dangerous)"
  fi

  printf '  \033[1;31m⚠️  This is destructive.\033[0m To proceed, type the agent id \033[1m%s\033[0m and press ENTER\n' "$CLUSTER_NAME" >&2
  printf '  \033[1m(or anything else to abort)\033[0m: ' >&2
  local answer=""
  IFS= read -r answer <"$tty" || true
  if [ "$answer" != "$CLUSTER_NAME" ]; then
    printf '  \033[1;33m🛑 confirmation did not match — aborted, nothing changed.\033[0m\n' >&2
    exit 130
  fi
}

remove() {
  if [ "$RELEASE_FOUND" = true ]; then
    log "uninstalling Helm release '$RELEASE_NAME'"
    if [ "$DRY_RUN" = true ]; then
      printf '\033[2m# helm uninstall %s -n %s --wait --timeout %s\033[0m\n' "$RELEASE_NAME" "$NAMESPACE" "$WAIT_TIMEOUT" >&2
    else
      helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout "$WAIT_TIMEOUT" >&2 \
        || warn "helm uninstall reported an error (continuing)"
    fi
  else
    warn "no Helm release '$RELEASE_NAME' in ns/$NAMESPACE — skipping helm uninstall"
  fi

  if [ "$REMOVE_NAMESPACE" = true ]; then
    log "deleting namespace '$NAMESPACE'"
    if [ "$DRY_RUN" = true ]; then
      printf '\033[2m# kubectl delete namespace %s --ignore-not-found\033[0m\n' "$NAMESPACE" >&2
    else
      kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false >&2 || true
    fi
  fi

  if [ "$REMOVE_FEDERATION" = true ]; then
    log "deleting ClusterFederatedTrustDomain '$MCP_FEDERATION_NAME'"
    if [ "$DRY_RUN" = true ]; then
      printf '\033[2m# kubectl delete clusterfederatedtrustdomain %s --ignore-not-found\033[0m\n' "$MCP_FEDERATION_NAME" >&2
    else
      kubectl delete clusterfederatedtrustdomain "$MCP_FEDERATION_NAME" --ignore-not-found >&2 || true
    fi
  fi
}

done_msg() {
  printf '\n' >&2
  printf '  \033[1;32m✅ pico-agent removed from \033[1;36m%s\033[1;32m.\033[0m\n' "$CLUSTER_NAME" >&2
  if [ "$REMOVE_FEDERATION" != true ]; then
    printf '  \033[2m(ClusterFederatedTrustDomain %s kept — set REMOVE_FEDERATION=true to delete)\033[0m\n' "$MCP_FEDERATION_NAME" >&2
  fi
  printf '  \033[2m🤖 Remember to deregister the agent in pico-mcp (id: %s).\033[0m\n\n' "$CLUSTER_NAME" >&2
}

main() {
  preflight
  discover
  summarize
  confirm
  remove
  done_msg
}

main "$@"
