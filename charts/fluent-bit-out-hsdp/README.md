# fluent-bit-out-hsdp

<!-- This README.md is generated. Please edit README.md.gotmpl -->

![Version: 0.0.14](https://img.shields.io/badge/Version-0.0.14-informational?style=flat-square) ![AppVersion: 1.9.9](https://img.shields.io/badge/AppVersion-1.9.9-informational?style=flat-square)

Installs the Fluentbit HSP out plugin.

**Homepage:** <https://fluentbit.io/>

## Quick Installation

To install the helm chart with default values run following command.
The [Values](#Values) section describes the configuration options for this chart.

```shell
helm install [RELEASE_NAME] .
```

## Uninstallation

To uninstall the Helm chart run following command.

\```shell
helm uninstall [RELEASE_NAME]
\```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| loafoe | <andy.loafoe@gmail.com> |  |

## Source Code

* <https://github.com/philips-software/fluent-bit-out-hsdp/>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://fluent.github.io/helm-charts | fluent-bit | 0.20.9 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fluent-bit.command[0] | string | `"/fluent-bit/bin/fluent-bit"` |  |
| fluent-bit.command[1] | string | `"-c"` |  |
| fluent-bit.command[2] | string | `"/fluent-bit/etc/fluent-bit.conf"` |  |
| fluent-bit.command[3] | string | `"-e"` |  |
| fluent-bit.command[4] | string | `"/out/out_hsdp.so"` |  |
| fluent-bit.config.outputs | string | `"[OUTPUT]\n    Name hsdp\n    Match kube.*\n\n[OUTPUT]\n    Name hsdp\n    Match host.*\n"` |  |
| fluent-bit.extraVolumeMounts[0].mountPath | string | `"/out"` |  |
| fluent-bit.extraVolumeMounts[0].name | string | `"plugins"` |  |
| fluent-bit.extraVolumes[0].emptyDir | object | `{}` |  |
| fluent-bit.extraVolumes[0].name | string | `"plugins"` |  |
| fluent-bit.initContainers[0].command[0] | string | `"cp"` |  |
| fluent-bit.initContainers[0].command[1] | string | `"/plugins/out_hsdp.so"` |  |
| fluent-bit.initContainers[0].command[2] | string | `"/out"` |  |
| fluent-bit.initContainers[0].image | string | `"philipssoftware/fluent-bit-out-hsdp-init:latest"` |  |
| fluent-bit.initContainers[0].name | string | `"copy-plugin"` |  |
| fluent-bit.initContainers[0].volumeMounts[0].mountPath | string | `"/out"` |  |
| fluent-bit.initContainers[0].volumeMounts[0].name | string | `"plugins"` |  |
