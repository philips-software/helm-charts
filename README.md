# philips-software

[![MIT License](https://img.shields.io/github/license/philips-labs/helm-charts?style=for-the-badge)](https://opensource.org/licenses/MIT)

This repository hosts philips-software [Helm](https://helm.sh) charts.

## Add Helm repository

```bash
helm repo add philips-labs https://philips-software.github.io/helm-charts/
helm repo update
```

## Add more charts to this repository

Add your helm repository as a submodule to this repository.

e.g.

```bash
git submodule add git@github.com:philips-software/fluent-bit-out-hsdp.git charts/fluent-bit-out-hsdp
```

Also ensure to add your chart to the dependabot config so it will automatically create PRs for updates to your chart.

e.g.

```yml
  - package-ecosystem: "gitsubmodule"
    directory: "/charts/fluent-bit-out-hsdp"
    schedule:
      interval: "daily"
```
