# CONTRIBUTING

:tada: Thanks for your interest in contributing to this project. In this document we outline a few guidelines to ease the way your contributions flow into this project.

## Commit style

Ensure you have clear and concise commits, written in the present tense. See [Kubernetes commit message guidelines](https://www.kubernetes.dev/docs/guide/pull-requests/#commit-message-guidelines) for a more detailed explanation of our approach.

```diff
+ git commit -m "Bump fluent-bit-out-hsdp chart to version 0.4.0"
- git commit -m "Bumped fluent-bit-out-hsdp chart to version 0.4.0"
```

## PRs

Stick with one feature/chart per branch. This allows us to make small controlled releases of the charts and makes it easy for us to review PRs.

Ensure your branch is rebased on top of main before issuing your PR. This to keep a clean Git history and to ensure your changes are working with the latest main branch changes. This also reduces the chance of failing releases.

```bash
git checkout main
git pull
git checkout «your-branch»
git rebase main
```

## Bumping helm chart dependencies

When bumping any dependency in Chart.yaml ensure you also update the Chart.lock file.

```shell
helm dependency update charts/«chart-name»
helm dependency build charts/«chart-name»
```

## Generating documentation

Any changes to Chart.yaml or values.yaml require an update of the README.md. This update can easily be generated using [helm-docs][].

```shell
helm-docs -g charts/«chart-name»
```

## Chart version contract

`chart-releaser` runs with `skip_existing: true`: a chart whose contents changed but whose `version:` didn't move is silently **not** released, with nothing on the PR to show for it. So any PR that changes a chart's contents must also bump that chart's own `version:` (patch), and, for a chart that ships an `install.sh` self-verify marker (`INSTALL_SH_CHART_VERSION`), keep the marker equal to `version:` — a mismatch makes `action-helm-chart-repo` skip packaging the chart.

This is enforced in two places:

- `version-guard` in `Lint and Test Charts` fails the PR if a changed chart's `version:` wasn't bumped, or if its `install.sh` marker doesn't match. Renovate PRs satisfy this automatically: the `bumpVersions` rule in `.github/renovate.json5` bumps `version:` and the `install.sh` marker together whenever it bumps a tracked dependency.
- `prepare-release.sh`, run from `release.yml` on the push to `main`, is the safety net: for every chart changed in the push it bumps any still-unmoved `version:`, reconciles any still-mismatched `install.sh` marker, and regenerates the helm-docs README for every changed chart — independent of who (if anyone) already bumped the version. It's idempotent, so a repeated push is a no-op.

If `version-guard` fails on your PR, fix it locally against `origin/main` and commit:

```shell
.github/bump-chart-versions.sh origin/main
.github/regen-chart-docs.sh origin/main
```

A bump missed before merge is still picked up on the push to `main` by `prepare-release.sh`.

[helm-docs]: https://github.com/norwoodj/helm-docs "The helm-docs tool auto-generates documentation from helm charts into markdown files."
