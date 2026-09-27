# zitadel-bootstrap

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

Deploys [Zitadel](https://zitadel.com/) via ArgoCD: CNPG Postgres (static credentials, no Bitnami), standard username/password sign-in out of the box, and Gateway API ingress via the upstream chart's own native HTTPRoute support.

## Prerequisites

- CloudNativePG operator installed cluster-wide (see `cloudnative-pg-operator`).
- A Gateway API `Gateway` for `ingress.httpRoute.sharedGatewayName` (defaults to the shared `platform` Gateway in `kube-system`, same as `langfuse-bootstrap`/`agentgateway-bootstrap`) when `ingress.httpRoute.enabled: true`.

## Credentials

`credentials.masterkey`, `credentials.postgresPassword`, and `credentials.adminPassword` are **static values, not generated at install time** — override every one of them for any real deployment. See the comments in `values.yaml` for generation commands. Never let these become templated/random: ArgoCD re-renders this chart via `helm template` on every sync, and a regenerated masterkey or password locks out the running instance.

## Signing in

Default admin: `credentials.adminUsername` (default `zitadel-admin`) / `credentials.adminPassword`. The first login forces a password change (`PasswordChangeRequired: true`).

With `ingress.httpRoute.enabled: false` (default), reach Zitadel via port-forward:

```bash
kubectl port-forward svc/zitadel 8080:8080 -n zitadel-system
```

Then browse to http://localhost:8080.

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
