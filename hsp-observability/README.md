# hsp-observability

Deploys a pre-configured Grafana Alloy agent using Argo CD.

Once deployed, the agent will:

* Collect and forward all pod logs.
* Gather metrics from endpoints defined in ServiceMonitors.
* Transmit Kubernetes events as logs.
* Establish an in-cluster OTLP endpoint for applications to send trace data.

## Deployment

### Argo CD CLI

* Use `argocd login` to establish a session with your cluster
* Create the Argo CD app:

```shell
argocd app create hsp-observability \
    --repo https://github.com/philips-software/helm-charts \
    --revision kustomize \
    --path kustomize/hsp-observability \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --config-management-plugin envsubst \
    --sync-policy auto	
```

### Using the Argo CD UI

* Login the the Argo CD UI as `admin`
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
 
