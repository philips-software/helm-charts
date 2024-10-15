# hsp-observability

Deploys a pre-configured [k8s-monitoring](https://artifacthub.io/packages/helm/grafana/k8s-monitoring) Helm chart to your Argo CD.

Once deployed, the chart will:

* Collect and forward all pod logs.
* Gather metrics from endpoints defined in ServiceMonitors.
* Transmit Kubernetes events as logs.
* Establish an in-cluster OTLP endpoint for applications to send trace data.

## Deployment

### Using the Argo CD CLI

* Use `argocd login` to establish a session with your cluster
* Create the Argo CD app:

```shell
argocd app create hsp-observability \
    --repo https://github.com/philips-software/helm-charts \
    --revision kustomize \
    --path hsp-observability/kustomize \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --config-management-plugin envsubst \
    --sync-policy auto	
```

### For HSP AWS Platform managed clusters

Use the `hsp-aws-platform` overlay:

```shell
argocd app create hsp-observability \
    --repo https://github.com/philips-software/helm-charts \
    --revision kustomize \
    --path hsp-observability/kustomize/overlays/hsp-aws-platform \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --config-management-plugin envsubst \
    --sync-policy auto	
```

### Using the Argo CD UI

* Log into the Argo CD UI as `admin`
* Click the `+ New App` button
* General:
  - Application Name: `hsp-observability`
  - Project Name: `default`
  - Sync Policy: `Automatic`
  - [x] Prune Resources
  - [x] Self Heal 
* Source:
  - Repository URL: `https://github.com/philips-software/helm-charts`
  - Revision: `kustomize`
  - Path: `kustomize/hsp-observability`
* Destination:
  - Cluster URL: `https://kubernetes.default.svc`
  - Namespace: `argocd`
* Select Plugin tab:
  - Plugin: `envsubst`
* Click `Create` 

## API Key

The exporter must authenticate with the regional OTLP endpoint using the API key provided by the HSP Managed Observability team.
Store this API key in a Kubernetes secret named hsp-observability with the key field set to api_key.

### Example secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hsp-observability
  namespace: hsp-observability
type: Opaque
data:
  host: aHR0cHM6Ly9vdGxwLWdhdGV3YXkub2JzLXVzLWVhc3QtY3QuaHNwLnBoaWxpcHMuY29t 
  key: bHN0X2tleWhlcmU=
```

Use kubectl to apply: `kubectl apply -f secret.yaml`
