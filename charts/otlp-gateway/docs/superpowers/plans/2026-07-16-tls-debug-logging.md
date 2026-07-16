# otlp-gateway TLS Handshake Error Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Caddy's global `debug` option (which unlocks `http.stdlib` TLS handshake error logs) turn on automatically when `log.level` is `debug` or `authn.clientCa.debug` is `true`, without changing the verbosity of ordinary access logs.

**Architecture:** Add one conditional `debug` line to the global options block in `config/Caddyfile`. No new values.yaml keys — reuse the existing `log.level` and `authn.clientCa.debug` values. Bump the chart patch version and regenerate `README.md` via `helm-docs`.

**Tech Stack:** Helm chart templating (Go templates), Caddy Caddyfile syntax, `helm template` for verification, `helm-docs` for README generation.

## Global Constraints

- Reuse existing values: `.Values.log.level` and `.Values.authn.clientCa.debug`. Do not add a new values.yaml key (per approved spec, `docs/superpowers/specs/2026-07-16-tls-debug-logging-design.md`).
- Global `debug` must NOT override the per-server-block access log `level` — those already set `level {{ .Values.log.level }}` explicitly and must remain the sole control for request-log verbosity.
- Condition to add: `{{- if or (eq .Values.log.level "debug") .Values.authn.clientCa.debug }}` around a bare `debug` line, placed in the global options block (top of `config/Caddyfile`, after `admin :2019`, before `servers {`).
- Chart lives at `/Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway`. Current chart version in `Chart.yaml` is `0.60.0` — bump to `0.60.1` (patch, backward-compatible template-only change).

---

### Task 1: Add conditional global `debug` directive and verify rendering

**Files:**
- Modify: `charts/otlp-gateway/config/Caddyfile:1-15` (global options block)
- Modify: `charts/otlp-gateway/values.yaml:23-24` (comment on `authn.clientCa.debug`)
- Modify: `charts/otlp-gateway/Chart.yaml:3` (version bump)
- Regenerate: `charts/otlp-gateway/README.md` (via `helm-docs`, comment-driven — no manual edits)

**Interfaces:**
- Consumes: existing values `.Values.log.level` (string, default `"error"`) and `.Values.authn.clientCa.debug` (bool, default `false`), both already defined in `values.yaml`.
- Produces: nothing consumed by other tasks — this is the only task in the plan.

- [ ] **Step 1: Confirm current rendered output has no `debug` line (baseline)**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm template test . --show-only templates/cm.yaml | grep -n "debug" || echo "NO DEBUG LINE (expected baseline)"
```
Expected output: `NO DEBUG LINE (expected baseline)` (the global options block currently has no `debug` directive; the only "debug" occurrences today are inside the `client_ca { debug ... }` and `spiffe { debug ... }` plugin blocks further down).

- [ ] **Step 2: Edit `config/Caddyfile` to add the conditional global debug directive**

Open `charts/otlp-gateway/config/Caddyfile`. Current lines 1-15:

```caddy
{
  order token first
  {{- if .Values.caddy.payloadsize.enabled }}
  order payloadsize after token
  {{- end }}
  admin :2019

  servers {
    metrics
  }

  storage file_system {
    root /data
  }
}
```

Replace with:

```caddy
{
  order token first
  {{- if .Values.caddy.payloadsize.enabled }}
  order payloadsize after token
  {{- end }}
  admin :2019

  {{- if or (eq .Values.log.level "debug") .Values.authn.clientCa.debug }}
  debug
  {{- end }}

  servers {
    metrics
  }

  storage file_system {
    root /data
  }
}
```

- [ ] **Step 3: Update the comment on `authn.clientCa.debug` in `values.yaml`**

Current (`charts/otlp-gateway/values.yaml:23-24`):

```yaml
    # Enable debug logging for client certificate authentication
    debug: false
```

Replace with:

```yaml
    # Enable debug logging for client certificate authentication.
    # Also enables Caddy's global debug mode, which surfaces TLS handshake
    # errors (e.g. expired/untrusted/missing client certs) via the
    # http.stdlib logger. Does not affect per-request access log verbosity,
    # which is controlled independently by log.level.
    debug: false
```

- [ ] **Step 4: Verify rendering with `authn.clientCa.debug=true`**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm template test . --set authn.clientCa.enabled=true --set authn.clientCa.debug=true --show-only templates/cm.yaml | sed -n '1,20p'
```
Expected: the global options block (top of the rendered Caddyfile, before `servers {`) contains a bare `debug` line, e.g.:
```
{
  order token first
  admin :2019

  debug

  servers {
```

- [ ] **Step 5: Verify rendering with `log.level=debug` (clientCa disabled)**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm template test . --set log.level=debug --show-only templates/cm.yaml | sed -n '1,20p'
```
Expected: same as Step 4 — global options block contains a bare `debug` line — even though `authn.clientCa.enabled` is false.

- [ ] **Step 6: Verify default rendering has no global `debug` line, but access log level is untouched**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm template test . --show-only templates/cm.yaml > /tmp/otlp-gateway-default.yaml
sed -n '1,20p' /tmp/otlp-gateway-default.yaml
grep -n "level error" /tmp/otlp-gateway-default.yaml
```
Expected: the global options block has no `debug` line (matches Step 1 baseline), and `grep` finds `level error` lines inside the `:8080` (and `:8443` if loadbalancer enabled) server blocks' `log { }` stanzas — confirming access-log verbosity is unaffected by this change.

- [ ] **Step 7: Verify with both loadbalancer and clientCa enabled (full render including :8443 block)**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm template test . \
  --set loadbalancer.enabled=true \
  --set environmentConfig.clusterFqdn=example.com \
  --set authn.clientCa.enabled=true \
  --set authn.clientCa.debug=true \
  --show-only templates/cm.yaml > /tmp/otlp-gateway-full.yaml
grep -n "debug" /tmp/otlp-gateway-full.yaml
```
Expected output includes exactly one bare `debug` line in the global options block, plus the existing `debug {{ .Values.authn.clientCa.debug }}` → `debug true` line inside the `client_ca { }` plugin block further down (that one is pre-existing behavior, unchanged by this task).

- [ ] **Step 8: Bump chart version**

Open `charts/otlp-gateway/Chart.yaml`. Change:
```yaml
version: 0.60.0
```
to:
```yaml
version: 0.60.1
```

- [ ] **Step 9: Regenerate README.md via helm-docs**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm-docs --chart-search-root=.
git diff README.md
```
Expected: `git diff` shows the `authn.clientCa.debug` description row unchanged (helm-docs pulls the type/default, not the free-text comment above the key — verify by inspecting the diff; if the table description does pick up part of the comment, confirm it still reads sensibly as a single-line table cell).

- [ ] **Step 10: Run `helm lint`**

Run:
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
helm lint .
```
Expected: `0 chart(s) failed`

- [ ] **Step 11: Commit**

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts
git add charts/otlp-gateway/config/Caddyfile charts/otlp-gateway/values.yaml charts/otlp-gateway/Chart.yaml charts/otlp-gateway/README.md
git commit -m "feat(otlp-gateway): enable Caddy global debug on log.level=debug or clientCa.debug for TLS handshake error logging (#288)"
```

---

## Post-plan verification (not a task — run after Task 1 is committed)

Confirm the full acceptance criteria from the spec in one pass:

```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/otlp-gateway
# 1. Baseline: no debug anywhere in global options
helm template test . --show-only templates/cm.yaml | awk '/^\{/{p=1} p&&/servers \{/{exit} p' | grep -c "^\s*debug\s*$"
# Expected: 0

# 2. clientCa.debug=true triggers global debug
helm template test . --set authn.clientCa.enabled=true --set authn.clientCa.debug=true --show-only templates/cm.yaml | awk '/^\{/{p=1} p&&/servers \{/{exit} p' | grep -c "^\s*debug\s*$"
# Expected: 1

# 3. log.level=debug triggers global debug
helm template test . --set log.level=debug --show-only templates/cm.yaml | awk '/^\{/{p=1} p&&/servers \{/{exit} p' | grep -c "^\s*debug\s*$"
# Expected: 1
```
