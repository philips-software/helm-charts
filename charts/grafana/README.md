# grafana

![Version: 0.77.0](https://img.shields.io/badge/Version-0.77.0-informational?style=flat-square)

Deploys Grafana to a cluster

## SSO configuration

By default this app is configured for SSO. It expects the SSO credentials to be available in the `grafana-sso-creds`
secret in the same namespace as the app. The secret should have the following fields:

- `clientId`: The client ID for the SSO application
- `clientSecret`: The client secret for the SSO application
- `issuerUrl`: The URL of the SSO issuer

### Provisioning `grafana-sso-creds` via the Dex Provider Client CR

This chart does **not** create the `grafana-sso-creds` secret itself — Dex (`dex-issuer`) and its
Crossplane connector-management plane (`provider-dex`) typically run on a separate **hub** cluster,
not on the cluster where this Grafana is deployed. There is no cross-cluster automation for this
yet, so the OAuth2 client must be registered against Dex manually and its credentials copied to
this cluster by hand. Steps:

1. **On the hub cluster** running `dex-issuer`/`provider-dex`, pick (or create) a namespace that
   already has a `ProviderConfig` (`dex.crossplane.io/v1alpha1`) pointing at that Dex instance —
   see `dex-issuer`'s `provider.providerConfigNamespaces` value. If none of the existing
   `ProviderConfig`s live in a namespace you can use, add one there (mirroring
   `dex-issuer/templates/providerconfig-dex.yaml`) rather than creating it in this chart, since
   this chart has no visibility into the hub cluster's PKI/endpoint.

2. **On the hub cluster**, create a `Client` CR (`oauth.dex.crossplane.io/v1`) for this Grafana
   instance, writing its connection secret to a throwaway name in that namespace:

   ```yaml
   apiVersion: oauth.dex.crossplane.io/v1
   kind: Client
   metadata:
     name: grafana-<cluster-name>       # unique per Grafana instance across the hub
     namespace: <namespace-with-providerconfig>
   spec:
     forProvider:
       id: grafana-<cluster-name>
       name: "Grafana (<cluster-name>)"
       redirectURIs:
         - https://<grafana-host>/login/generic_oauth   # e.g. gf.<clusterFqdn>
     providerConfigRef:
       kind: ProviderConfig
       name: default
     writeConnectionSecretToRef:
       name: grafana-<cluster-name>-sso-creds
   ```

   Once `Ready`/`Synced`, this produces a secret with `clientId`, `clientSecret`, and `issuerUrl`
   keys — exactly the shape `grafana-sso-creds` needs.

3. **Copy the resulting secret to this cluster** into the same namespace as the Grafana release,
   named `grafana-sso-creds`:

   ```sh
   kubectl --context <hub-context> get secret grafana-<cluster-name>-sso-creds \
     -n <namespace-with-providerconfig> -o json \
     | jq '{apiVersion,kind,type,data,metadata:{name:"grafana-sso-creds",namespace:"<release-namespace>"}}' \
     | kubectl --context <spoke-context> apply -f -
   ```

   Re-run this whenever the client secret is rotated (the `Client` CR's `spec.forProvider.secret`
   is empty by default, so Dex generates and keeps a stable secret — this only needs to be redone
   if the `Client` CR itself is recreated).

4. Set `grafana.ssoAuthEnabled: true` in this chart's values once the secret exists, then sync.

If you're deploying to a cluster where Dex and Grafana genuinely run side-by-side (uncommon), the
same `ProviderConfig`/`Client` pattern applies — just create both CRs locally instead of on a
separate hub.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argocd.namespace | string | `"argocd"` |  |
| argocd.project | string | `"default"` |  |
| crossplaneProviders.cascadeDelete | bool | `false` |  |
| crossplaneProviders.gf.datasources | list | `[]` |  |
| crossplaneProviders.gf.debug | bool | `false` |  |
| crossplaneProviders.gf.enabled | bool | `true` |  |
| crossplaneProviders.gf.tag | string | `"v0.10.0"` |  |
| crossplaneProviders.orgmapper.debug | bool | `false` |  |
| crossplaneProviders.orgmapper.enabled | bool | `true` |  |
| database.cnpg | bool | `true` |  |
| database.restoreFromSnapshot | bool | `false` |  |
| database.restoreFromVolumeSnapshot.enabled | bool | `false` |  |
| database.restoreFromVolumeSnapshot.sourceIdentifier | string | `""` |  |
| database.restoreFromVolumeSnapshot.storageClassName | string | `""` |  |
| database.snapshotId | string | `"grafana-202501201706"` |  |
| database.snapshots.enabled | bool | `false` |  |
| database.snapshots.snapshotClassName | string | `""` |  |
| database.snapshots.storageClassName | string | `""` |  |
| datasources.gatewayUrl | string | `"http://datasource-gateway.otlp-gateway.svc.cluster.local"` |  |
| datasources.loki.enabled | bool | `false` |  |
| datasources.mimir.enabled | bool | `false` |  |
| datasources.tempo.enabled | bool | `false` |  |
| environmentConfig.clusterFqdn | string | `""` |  |
| environmentConfig.customFqdn | string | `""` |  |
| environmentConfig.resourcePrefix | string | `""` |  |
| grafana.authProxy.autoSignUp | bool | `true` |  |
| grafana.authProxy.caddy.autoLoginEmail | string | `""` |  |
| grafana.authProxy.caddy.autoLoginRole | string | `"Viewer"` |  |
| grafana.authProxy.caddy.autoLoginUser | string | `"viewer"` |  |
| grafana.authProxy.caddy.enabled | bool | `false` |  |
| grafana.authProxy.caddy.image | string | `"caddy:2-alpine"` |  |
| grafana.authProxy.caddy.resources.limits.memory | string | `"64Mi"` |  |
| grafana.authProxy.caddy.resources.requests.cpu | string | `"10m"` |  |
| grafana.authProxy.caddy.resources.requests.memory | string | `"32Mi"` |  |
| grafana.authProxy.caddy.trustedIPs | list | `[]` |  |
| grafana.authProxy.caddy.trustedProxyCIDRs | list | `[]` |  |
| grafana.authProxy.enableLoginToken | bool | `false` |  |
| grafana.authProxy.enabled | bool | `false` |  |
| grafana.authProxy.headerName | string | `"X-WEBAUTH-USER"` |  |
| grafana.authProxy.headerProperty | string | `"username"` |  |
| grafana.authProxy.headersEmail | string | `""` |  |
| grafana.authProxy.headersGroups | string | `""` |  |
| grafana.authProxy.headersLogin | string | `""` |  |
| grafana.authProxy.headersName | string | `""` |  |
| grafana.authProxy.headersRole | string | `""` |  |
| grafana.authProxy.syncTtl | int | `60` |  |
| grafana.authProxy.whitelist | string | `""` |  |
| grafana.connector | string | `""` |  |
| grafana.downloadDashboardsResources.limits.memory | string | `"24Mi"` |  |
| grafana.downloadDashboardsResources.requests.cpu | string | `"10m"` |  |
| grafana.downloadDashboardsResources.requests.memory | string | `"16Mi"` |  |
| grafana.env | object | `{}` |  |
| grafana.extraInitContainers | list | `[]` |  |
| grafana.extraVolumes | list | `[]` |  |
| grafana.httpRoute.enabled | bool | `true` |  |
| grafana.httpRoute.host | string | `"gf"` |  |
| grafana.httpRoute.sharedGatewayName | string | `"platform"` |  |
| grafana.httpRoute.sharedGatewayNamespace | string | `"kube-system"` |  |
| grafana.ingress.enabled | bool | `false` |  |
| grafana.ingress.host | string | `"gf"` |  |
| grafana.ingress.ingressClassName | string | `"nginx"` |  |
| grafana.logLevel | string | `"info"` |  |
| grafana.pluginSync.enabled | bool | `false` |  |
| grafana.pluginSync.schedule | string | `"*/15 * * * *"` |  |
| grafana.plugins | list | `[]` |  |
| grafana.replicas | int | `2` |  |
| grafana.resources.limits.memory | string | `"1Gi"` |  |
| grafana.resources.requests.cpu | string | `"200m"` |  |
| grafana.resources.requests.memory | string | `"256Mi"` |  |
| grafana.ssoAuthEnabled | bool | `false` |  |
| grafana.tenants | list | `[]` |  |
| grafanaChart.releaseName | string | `"gf"` |  |
| grafanaChart.version | string | `"12.8.0"` |  |
| useCustomFqdn | bool | `true` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
