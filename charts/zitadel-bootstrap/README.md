# zitadel-bootstrap

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Deploys [Zitadel](https://zitadel.com/) via ArgoCD: CNPG Postgres (static credentials, no Bitnami), standard username/password sign-in out of the box, and a single Gateway API HTTPRoute of this chart's own (not the upstream chart's native Gateway API support — see the design spec's "Ingress" section for why).

## Prerequisites

- CloudNativePG operator installed cluster-wide (see `cloudnative-pg-operator`).
- A Gateway API `Gateway` for `ingress.httpRoute.sharedGatewayName` (defaults to the shared `platform` Gateway in `kube-system`, same as `langfuse-bootstrap`/`agentgateway-bootstrap`) when `ingress.httpRoute.enabled: true`.
- The namespace `.Values.namespace` (default `zitadel-system`) must already exist before a *first-ever* `helm install` — this chart's own CNPG Secret/Cluster/HTTPRoute apply directly into it, and nothing in this chart creates it (ArgoCD's `CreateNamespace=true` only creates it for the *child* Application's own sync, one step later). `kubectl create namespace zitadel-system` once, or use `helm upgrade --install` against a cluster where a prior attempt already created it.

## Credentials

`credentials.masterkey`, `credentials.postgresPassword`, and `credentials.adminPassword` are **static values, not generated at install time** — override every one of them for any real deployment. See the comments in `values.yaml` for generation commands. Never let these become templated/random: ArgoCD re-renders this chart via `helm template` on every sync, and a regenerated masterkey or password locks out the running instance.

None of these three values reach the upstream chart as plaintext in the ArgoCD `Application`'s own spec (which anyone with read access to `Application` objects — not just `Secret` objects — can see, e.g. via the ArgoCD UI's Manifest view). The masterkey is passed via `zitadel.masterkeySecretName` pointing at this chart's own `zitadel-credentials` Secret; the Postgres and admin passwords are injected via `env`/`secretKeyRef` (`ZITADEL_DATABASE_POSTGRES_USER_PASSWORD`, `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD` — Zitadel's own env-var override convention).

## Signing in

Default admin: `credentials.adminUsername` (default `zitadel-admin`) / `credentials.adminPassword`. The first login forces a password change (`PasswordChangeRequired: true`).

With `ingress.httpRoute.enabled: true`, sign in at `https://<ingress.httpRoute.host>.<environmentConfig.clusterFqdn>`.

With `ingress.httpRoute.enabled: false` (default), only the main API/console is reachable via port-forward — the split login v2 UI (a separate `zitadel-login` Service) needs its own origin to work correctly, which a single port-forward can't provide:

```bash
kubectl port-forward svc/zitadel 8080:8080 -n zitadel-system
```

Then browse to http://localhost:8080. For an actual local sign-in flow, enable `ingress.httpRoute.enabled` against a real (even if just local/dev) Gateway instead.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argoProject | string | `"default"` |  |
| credentials.adminPassword | string | `"changeme-Admin-Password1!"` |  |
| credentials.adminUsername | string | `"zitadel-admin"` |  |
| credentials.masterkey | string | `"changeme-please-override-32bytes"` |  |
| credentials.postgresPassword | string | `"changeme-postgres-password-please-override"` |  |
| database.clusterName | string | `""` |  |
| database.databaseName | string | `"zitadel"` |  |
| database.instances | int | `1` |  |
| database.resources.limits.memory | string | `"512Mi"` |  |
| database.resources.requests.cpu | string | `"50m"` |  |
| database.resources.requests.memory | string | `"128Mi"` |  |
| database.storage.size | string | `"5Gi"` |  |
| database.storage.storageClass | string | `""` |  |
| environmentConfig.accountId | string | `""` |  |
| environmentConfig.clusterFqdn | string | `""` |  |
| environmentConfig.region | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| firstInstance.orgName | string | `"ZITADEL"` |  |
| ingress.httpRoute.enabled | bool | `false` |  |
| ingress.httpRoute.host | string | `"zitadel"` |  |
| ingress.httpRoute.sharedGatewayName | string | `"platform"` |  |
| ingress.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| namespace | string | `"zitadel-system"` |  |
| zitadelChart.repoURL | string | `"https://charts.zitadel.com"` |  |
| zitadelChart.version | string | `"10.0.6"` |  |
