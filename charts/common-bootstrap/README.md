# common-bootstrap

![Version: 2.2.0](https://img.shields.io/badge/Version-2.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.52](https://img.shields.io/badge/AppVersion-0.0.52-informational?style=flat-square)

Common Bootstrap Helm chart.
Creates EnvironmentConfig from a ConfigMap, deploys crossplane-compositions,
and uses HelmApplication CRs to bootstrap platform components.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argocd.namespace | string | `"argocd"` |  |
| argocd.projects.apps.clusterResourceWhitelist[0].group | string | `"rbac.authorization.k8s.io"` |  |
| argocd.projects.apps.clusterResourceWhitelist[0].kind | string | `"ClusterRole"` |  |
| argocd.projects.apps.clusterResourceWhitelist[1].group | string | `"rbac.authorization.k8s.io"` |  |
| argocd.projects.apps.clusterResourceWhitelist[1].kind | string | `"ClusterRoleBinding"` |  |
| argocd.projects.apps.create | bool | `true` |  |
| argocd.projects.apps.description | string | `"Namespaced workloads bootstrapped alongside common-infra"` |  |
| argocd.projects.apps.destinationNamespaces[0] | string | `"k8s-observability-monitoring"` |  |
| argocd.projects.apps.destinationNamespaces[1] | string | `"otlp-gateway"` |  |
| argocd.projects.apps.destinationNamespaces[2] | string | `"monitoring"` |  |
| argocd.projects.apps.name | string | `"common-apps"` |  |
| argocd.projects.apps.sourceNamespaces[0] | string | `"k8s-observability-monitoring"` |  |
| argocd.projects.apps.sourceNamespaces[1] | string | `"otlp-gateway"` |  |
| argocd.projects.apps.sourceNamespaces[2] | string | `"monitoring"` |  |
| argocd.projects.apps.sourceRepos[0] | string | `"https://github.com/grafana/k8s-monitoring-helm"` |  |
| argocd.projects.apps.sourceRepos[1] | string | `"https://grafana-community.github.io/helm-charts"` |  |
| argocd.projects.apps.sourceRepos[2] | string | `"https://grafana.github.io/helm-charts"` |  |
| argocd.projects.apps.sourceRepos[3] | string | `"oci://ghcr.io/philips-software/helm-charts/otlp-gateway"` |  |
| argocd.projects.apps.sourceRepos[4] | string | `"oci://ghcr.io/philips-software/helm-charts/grafana"` |  |
| argocd.projects.apps.sourceRepos[5] | string | `"oci://ghcr.io/philips-software/helm-charts/*"` |  |
| argocd.projects.apps.sourceRepos[6] | string | `"ghcr.io/philips-software"` |  |
| argocd.projects.infra.clusterResourceWhitelist[0].group | string | `"*"` |  |
| argocd.projects.infra.clusterResourceWhitelist[0].kind | string | `"*"` |  |
| argocd.projects.infra.create | bool | `true` |  |
| argocd.projects.infra.description | string | `"Cluster-wide platform operators and CRDs bootstrapped by common-bootstrap"` |  |
| argocd.projects.infra.destinationNamespaces[0] | string | `"common-bootstrap"` |  |
| argocd.projects.infra.destinationNamespaces[1] | string | `"crossplane-system"` |  |
| argocd.projects.infra.destinationNamespaces[2] | string | `"cnpg-system"` |  |
| argocd.projects.infra.destinationNamespaces[3] | string | `"monitoring"` |  |
| argocd.projects.infra.name | string | `"common-infra"` |  |
| argocd.projects.infra.sourceNamespaces[0] | string | `"common-bootstrap"` |  |
| argocd.projects.infra.sourceNamespaces[1] | string | `"crossplane-system"` |  |
| argocd.projects.infra.sourceNamespaces[2] | string | `"cnpg-system"` |  |
| argocd.projects.infra.sourceNamespaces[3] | string | `"monitoring"` |  |
| argocd.projects.infra.sourceRepos[0] | string | `"https://github.com/philips-software/helm-charts"` |  |
| argocd.projects.infra.sourceRepos[1] | string | `"https://github.com/loafoe/crossplane-compositions"` |  |
| argocd.projects.infra.sourceRepos[2] | string | `"https://cloudnative-pg.io/charts/"` |  |
| argocd.projects.infra.sourceRepos[3] | string | `"https://grafana-community.github.io/helm-charts"` |  |
| argocd.projects.infra.sourceRepos[4] | string | `"oci://ghcr.io/philips-software/helm-charts/cloudnative-pg-operator"` |  |
| argocd.projects.infra.sourceRepos[5] | string | `"oci://ghcr.io/philips-software/helm-charts/*"` |  |
| argocd.projects.infra.sourceRepos[6] | string | `"ghcr.io/philips-software"` |  |
| argocdSyncAlerts.additionalLabels | object | `{}` |  |
| argocdSyncAlerts.enabled | bool | `false` |  |
| argocdSyncAlerts.frozenFor | string | `"6h"` |  |
| argocdSyncAlerts.namespace | string | `""` |  |
| argocdSyncAlerts.stuckFor | string | `"1h"` |  |
| argocdSyncAlerts.syncFailureFor | string | `"10m"` |  |
| argocdSyncAlerts.syncFailureWindow | string | `"15m"` |  |
| crossplaneCompositions.enabled | bool | `true` |  |
| crossplaneCompositions.path | string | `"kustomize"` |  |
| crossplaneCompositions.repoURL | string | `"https://github.com/loafoe/crossplane-compositions"` |  |
| environmentConfig.labels.config | string | `"dip-software"` |  |
| environmentConfig.name | string | `"hsp-addons-compat"` |  |
| harvester.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].key | string | `"node-role.kubernetes.io/control-plane"` |  |
| harvester.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].operator | string | `"Exists"` |  |
| harvester.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight | int | `100` |  |
| harvester.enabled | bool | `true` |  |
| harvester.image.pullPolicy | string | `"IfNotPresent"` |  |
| harvester.image.repository | string | `"docker.io/alpine/k8s"` |  |
| harvester.image.tag | string | `"1.37.1"` |  |
| harvester.nodeSelector | object | `{}` |  |
| harvester.serviceAccount.name | string | `"hsp-addons-harvester"` |  |
| harvester.tolerations[0].key | string | `"CriticalAddonsOnly"` |  |
| harvester.tolerations[0].operator | string | `"Exists"` |  |
| harvester.ttlSecondsAfterFinished | int | `600` |  |
| harvester.waitForConfigMapSeconds | int | `600` |  |
| helmApplications | object | `{}` |  |
| sourceConfigMap.name | string | `"hsp-addons"` |  |
| sourceConfigMap.namespace | string | `"hsp-addons"` |  |
| statefulSetImmutableReconciler.allowVolumeClaimChanges | bool | `false` |  |
| statefulSetImmutableReconciler.appFilter | list | `[]` |  |
| statefulSetImmutableReconciler.dryRun | bool | `false` |  |
| statefulSetImmutableReconciler.enabled | bool | `false` |  |
| statefulSetImmutableReconciler.image.tag | string | `"1.37.1"` |  |
| statefulSetImmutableReconciler.schedule | string | `"*/10 * * * *"` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
