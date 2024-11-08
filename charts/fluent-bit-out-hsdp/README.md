# fluent-bit-out-hsdp

<!-- This README.md is generated. Please edit README.md.gotmpl -->

![Version: 0.12.0](https://img.shields.io/badge/Version-0.12.0-informational?style=flat-square) ![AppVersion: 2.6.0](https://img.shields.io/badge/AppVersion-2.6.0-informational?style=flat-square)

Installs the Fluentbit HSP out plugin.

**Homepage:** <https://github.com/philips-software/fluent-bit-out-hsdp>

## Quick Installation

To install the helm chart with default values run following command.
The [Values](#Values) section describes the configuration options for this chart.

```shell
helm install [RELEASE_NAME] .
```

## Uninstallation

To uninstall the Helm chart run following command.

```shell
helm uninstall [RELEASE_NAME]
```
## Development

```shell
helm dependency update charts/fluent-bit-out-hsdp
helm dependency build charts/fluent-bit-out-hsdp
helm-docs -g charts/go-hello-world
```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| loafoe | <andy.loafoe@gmail.com> |  |

## Source Code

* <https://github.com/philips-software/fluent-bit-out-hsdp/>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://fluent.github.io/helm-charts | fluent-bit | 0.23.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fluent-bit.command[0] | string | `"/fluent-bit/bin/fluent-bit"` |  |
| fluent-bit.command[1] | string | `"-c"` |  |
| fluent-bit.command[2] | string | `"/fluent-bit/etc/fluent-bit.conf"` |  |
| fluent-bit.command[3] | string | `"-e"` |  |
| fluent-bit.command[4] | string | `"/out/out_hsdp.so"` |  |
| fluent-bit.config.filters | string | `"[FILTER]\n    Name kubernetes\n    Match kube.*\n    Merge_Log On\n    Keep_Log Off\n    K8S-Logging.Parser On\n    K8S-Logging.Exclude On\n[FILTER]\n    Name nest\n    Match kube.*\n    Operation lift\n    Nested_under kubernetes\n    Add_prefix kube_\n[FILTER]\n    Name modify\n    Match kube.*\n    Copy log logdata_message\n    Copy kube_host server_name\n    Copy kube_pod_name app_instance\n    Copy kube_container_name app_name\n    Copy kube_container_image app_version\n    Copy kube_namespace_name service_name\n    Copy stream category\n"` |  |
| fluent-bit.config.outputs | string | `"[OUTPUT]\n    Name hsdp\n    Match *\n"` |  |
| fluent-bit.extraVolumeMounts[0].mountPath | string | `"/out"` |  |
| fluent-bit.extraVolumeMounts[0].name | string | `"plugins"` |  |
| fluent-bit.extraVolumes[0].emptyDir | object | `{}` |  |
| fluent-bit.extraVolumes[0].name | string | `"plugins"` |  |
| fluent-bit.initContainers[0].command[0] | string | `"cp"` |  |
| fluent-bit.initContainers[0].command[1] | string | `"/plugins/out_hsdp.so"` |  |
| fluent-bit.initContainers[0].command[2] | string | `"/out"` |  |
| fluent-bit.initContainers[0].image | string | `"ghcr.io/philips-software/fluent-bit-out-hsdp:2.6.0"` |  |
| fluent-bit.initContainers[0].name | string | `"copy-plugin"` |  |
| fluent-bit.initContainers[0].resources.limits.cpu | string | `"500m"` |  |
| fluent-bit.initContainers[0].resources.limits.memory | string | `"512Mi"` |  |
| fluent-bit.initContainers[0].resources.requests.cpu | string | `"250m"` |  |
| fluent-bit.initContainers[0].resources.requests.memory | string | `"256Mi"` |  |
| fluent-bit.initContainers[0].volumeMounts[0].mountPath | string | `"/out"` |  |
| fluent-bit.initContainers[0].volumeMounts[0].name | string | `"plugins"` |  |
| fluent-bit.resources.limits.cpu | string | `"500m"` |  |
| fluent-bit.resources.limits.memory | string | `"512Mi"` |  |
| fluent-bit.resources.requests.cpu | string | `"250m"` |  |
| fluent-bit.resources.requests.memory | string | `"256Mi"` |  |
