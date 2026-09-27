# zitadel-bootstrap design

**Date**: 2026-09-27
**Status**: approved (in-chat design review), spec written for record

## Goal

A `zitadel-bootstrap` Helm chart, modeled after `langfuse-bootstrap` and
`agentgateway-bootstrap` for its Postgres usage, that wraps the upstream
[`zitadel/zitadel`](https://artifacthub.io/packages/helm/zitadel/zitadel/10.0.6)
chart (`https://charts.zitadel.com`, chart `zitadel`, version `10.0.6`).

Reach is: a functional Zitadel instance reachable at
`https://zitadel.dip-ce-k3s-eu.hsp.philips.com` on the `dip-ce-k3s-eu`
cluster, deployed entirely from this wrapper chart, with standard
username/password sign-in working out of the box (no SSO/OIDC dependency
for the initial admin).

- Default namespace: `zitadel-system`.
- Never use Bitnami images (user preference) — the upstream chart's
  bundled `postgresql` (Bitnami) subchart stays `enabled: false`; we bring
  our own CNPG `Cluster` instead, same as `langfuse-bootstrap` and
  `agentgateway-bootstrap`.

## Chart layout

```
charts/zitadel-bootstrap/
  Chart.yaml                          # no appVersion (see langfuse-bootstrap's own rationale)
  values.yaml
  config/zitadel-values.yaml          # tpl'd into the ArgoCD Application's valuesObject
  templates/
    _helpers.tpl
    postgres-cluster.yaml             # CNPG Cluster (bootstrap.initdb)
    postgres-secret.yaml              # static basic-auth Secret, owner role
    zitadel-helm.yaml                 # ArgoCD Application -> upstream chart
  README.md / README.md.gotmpl
```

No custom HTTPRoute template is needed — see "Ingress" below.

## ArgoCD Application source

Unlike `langfuse-bootstrap`'s OCI source, the upstream `zitadel` chart is
published on a classic Helm repo (`https://charts.zitadel.com`), same shape
as this repo's `grafana`/`dex-issuer` charts:

```yaml
source:
  chart: zitadel
  repoURL: https://charts.zitadel.com
  targetRevision: {{ .Values.zitadelChart.version | quote }}
  helm:
    releaseName: zitadel
    valuesObject:
      {{- (tpl (.Files.Get "config/zitadel-values.yaml") .) | nindent 8 }}
destination:
  server: https://kubernetes.default.svc
  namespace: {{ .Values.namespace }}
syncPolicy:
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
  automated:
    prune: true
    selfHeal: true
```

`zitadelChart.version` carries a
`# renovate: datasource=helm depName=zitadel registryUrl=https://charts.zitadel.com`
annotation (the classic-Helm-repo renovate convention used by
`dex-issuer`'s `dexChart.version`), default `10.0.6`.

## Postgres (CNPG, static credentials)

A plain CNPG `Cluster` (`postgres-cluster.yaml`), same shape as
`langfuse-bootstrap`'s:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ include "zitadel-bootstrap.postgresClusterName" . }}
spec:
  instances: {{ .Values.database.instances }}
  bootstrap:
    initdb:
      database: {{ .Values.database.databaseName | quote }}   # "zitadel"
      owner: {{ .Values.database.databaseName | quote }}
      secret:
        name: {{ include "zitadel-bootstrap.postgresClusterName" . }}-credentials
  storage: ...
  resources: ...  # requests only + memory limit, no CPU limit (user preference)
```

`postgres-secret.yaml` is a **static** `kubernetes.io/basic-auth` Secret
(`username: zitadel`, `password: .Values.credentials.postgresPassword`) —
never randomly generated, for the same reason `langfuse-bootstrap` pins its
`credentials.postgresPassword`: ArgoCD re-renders this chart via
`helm template` on every sync, so a regenerated password would break the
connection on the next sync.

### Wiring into the upstream chart

The CNPG cluster already creates the database *and* an owner role with full
privileges on it — there's no separate superuser step needed. So:

```yaml
# config/zitadel-values.yaml
initJob:
  command: "zitadel"   # skip upstream's own database/user/grant creation steps

zitadel:
  configmapConfig:
    Database:
      Postgres:
        Host: {{ include "zitadel-bootstrap.postgresClusterName" . }}-rw.{{ .Values.namespace }}.svc.cluster.local
        Port: 5432
        Database: {{ .Values.database.databaseName | quote }}
        User:
          Username: {{ .Values.database.databaseName | quote }}
          SSL:
            Mode: disable
        Admin:
          Username: {{ .Values.database.databaseName | quote }}
          ExistingDatabase: {{ .Values.database.databaseName | quote }}
          SSL:
            Mode: disable
  secretConfig:
    Database:
      Postgres:
        User:
          Password: {{ .Values.credentials.postgresPassword | quote }}
        Admin:
          Password: {{ .Values.credentials.postgresPassword | quote }}
```

The CNPG owner role acts as both "User" (runtime connections) and "Admin"
(the `zitadel init` schema-creation step) — confirmed against
`zitadel/zitadel`'s `cmd/initialise/init.go`: `initJob.command: "zitadel"`
only runs `verifyZitadel` (schema/table creation), skipping
`VerifyUser`/`VerifyDatabase`/`VerifyGrant`, so the Admin connection never
needs superuser, just ownership of its own database — which CNPG already
grants.

`sslmode: disable` matches how `langfuse-bootstrap`/`agentgateway-bootstrap`
already connect to their own in-cluster CNPG clusters (no TLS CA wiring in
either chart today).

## Credentials and secrets

Unlike `langfuse-k8s` (which needs an externally-created Secret for its own
app secrets), the upstream `zitadel` chart accepts `zitadel.masterkey` and
`zitadel.secretConfig` as **literal values** and creates its own Secret via
a `pre-install`-only hook — so no extra Secret template is needed on our
side for these:

```yaml
credentials:
  # 32 bytes exactly, printable ASCII. Generate: tr -dc A-Za-z0-9 </dev/urandom | head -c 32
  masterkey: "changeme-please-override-32bytes"  # 32 chars — verify with `wc -c` (no trailing newline) before reuse
  postgresPassword: "changeme-postgres-password-please-override"
  adminUsername: "zitadel-admin"
  # Must satisfy Zitadel's default password policy (upper+lower+digit).
  adminPassword: "changeme-Admin-Password1!"
```

Wired as:

```yaml
zitadel:
  masterkey: {{ .Values.credentials.masterkey | quote }}
  configmapConfig:
    FirstInstance:
      Org:
        Name: {{ .Values.firstInstance.orgName | quote }}
        Human:
          UserName: {{ .Values.credentials.adminUsername | quote }}
          PasswordChangeRequired: true
  secretConfig:
    FirstInstance:
      Org:
        Human:
          Password: {{ .Values.credentials.adminPassword | quote }}
```

`zitadel.masterkey` being a plain literal (not `masterkeySecretName`) is
safe against ArgoCD's repeated `helm template` re-renders specifically
*because* the upstream chart's own Secret-creation hook is
`helm.sh/hook: pre-install` only (not `pre-upgrade`) — it's created once and
never touched again, unlike `secretConfigAnnotations`/`configMap.annotations`
which do re-fire on every upgrade (those hold no long-lived secret material
that regenerating would break, so that's fine).

## Ingress

The upstream chart has **native** Gateway API support
(`gateway.httpRoute`, `login.gateway.httpRoute`, `gateway.grpcRoute`) —
unlike `langfuse-k8s`, no custom `httproute.yaml` template is needed here.
Our `ingress.httpRoute` toggle sets both of the upstream chart's own
HTTPRoute blocks to point at the same shared `platform` Gateway
(`kube-system`), same convention as `langfuse-bootstrap`'s
`ingress.httpRoute.{host,sharedGatewayName,sharedGatewayNamespace}` +
`environmentConfig.clusterFqdn`:

```yaml
# config/zitadel-values.yaml
{{- if .Values.ingress.httpRoute.enabled }}
zitadel:
  configmapConfig:
    ExternalDomain: {{ include "zitadel-bootstrap.host" . }}
    ExternalSecure: true
gateway:
  httpRoute:
    enabled: true
    parentRefs:
      - name: {{ .Values.ingress.httpRoute.sharedGatewayName }}
        namespace: {{ .Values.ingress.httpRoute.sharedGatewayNamespace }}
    hostnames:
      - {{ include "zitadel-bootstrap.host" . }}
login:
  gateway:
    httpRoute:
      enabled: true
      parentRefs:
        - name: {{ .Values.ingress.httpRoute.sharedGatewayName }}
          namespace: {{ .Values.ingress.httpRoute.sharedGatewayNamespace }}
      hostnames:
        - {{ include "zitadel-bootstrap.host" . }}
{{- end }}
```

`gateway.grpcRoute` stays disabled by default — browser access to the
Console UI and Login UI only needs HTTPRoute (Zitadel's v2 APIs speak
Connect-protocol/grpc-web over plain HTTP too); a native gRPC client would
need `grpcRoute.enabled: true` added later, out of scope for initial reach.

## values.yaml shape (top-level keys)

```yaml
zitadelChart:
  repoURL: https://charts.zitadel.com
  version: 10.0.6            # renovate: datasource=helm depName=zitadel registryUrl=https://charts.zitadel.com

argoProject: default

environmentConfig:
  resourcePrefix: ""
  region: ""
  accountId: ""
  clusterFqdn: ""

namespace: zitadel-system

ingress:
  httpRoute:
    enabled: false
    host: zitadel
    sharedGatewayName: platform
    sharedGatewayNamespace: kube-system

database:
  clusterName: ""             # defaults to "zitadel-db"
  instances: 1
  databaseName: zitadel
  storage:
    size: 5Gi
    storageClass: ""
  resources:
    requests: {cpu: 50m, memory: 128Mi}
    limits: {memory: 512Mi}

credentials:
  masterkey: "changeme-..."
  postgresPassword: "changeme-..."
  adminUsername: "zitadel-admin"
  adminPassword: "changeme-..."

firstInstance:
  orgName: ZITADEL

replicaCount: 1
resources: {requests: {cpu: 100m, memory: 256Mi}, limits: {memory: 512Mi}}

login:
  replicaCount: 1
  resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {memory: 256Mi}}
```

`validateConfig` helper fails fast (same convention as
`langfuse-bootstrap.validateConfig`) when: `argoProject` empty,
`zitadelChart.version` empty, `environmentConfig.clusterFqdn` empty while
`ingress.httpRoute.enabled` is true, any `credentials.*` value empty, or
`credentials.masterkey` is not exactly 32 bytes (`len (.Values.credentials.masterkey)`
— catches the single most common copy-paste mistake with this field before
it reaches the upstream chart, which fails the same way but only inside the
setup Job's logs).

## Testing / reach criteria

1. `helm template` renders cleanly against upstream chart `10.0.6`
   (pull it locally to diff templates before trusting field names against
   the live values schema).
2. Deploy to `dip-ce-k3s-eu` (namespace `zitadel-system`), confirm:
   - ArgoCD Application `Synced`/`Healthy`.
   - CNPG cluster `zitadel-db` reaches `Cluster Ready`.
   - `initJob`/`setupJob` complete successfully (`kubectl logs`).
   - `https://zitadel.dip-ce-k3s-eu.hsp.philips.com` loads the Console/Login
     UI and a login with `credentials.adminUsername`/`adminPassword`
     succeeds (forced password change accepted).
3. Record the live deployment in
   `/Users/andy/DEV/Philips/innovation-day/zitadel/` (values snapshot +
   README), matching the `langfuse`/`agentgateway` folders' convention —
   credentials redacted in the committed copy.

## Out of scope (initial reach)

- SSO/OIDC federation for the admin user (username/password only, per the
  ask).
- `gateway.grpcRoute` / native gRPC client access.
- HA (multiple CNPG instances, multiple Zitadel/Login replicas) — single
  instance/replica defaults, same as `langfuse-bootstrap`'s initial
  defaults.
- TLS to Postgres (`sslmode: disable`, in-cluster only).
