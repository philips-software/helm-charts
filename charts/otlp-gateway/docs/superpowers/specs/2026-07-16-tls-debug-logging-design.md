# otlp-gateway: TLS handshake error logging (mTLS debug)

Issue: https://github.com/philips-software/helm-charts/issues/288

## Problem

When `authn.clientCa.enabled: true`, Caddy performs mTLS client certificate
verification at the TLS layer, before any HTTP request completes. If a
client presents an expired, untrusted, or missing certificate, the TLS
handshake fails and the connection is dropped. Because the chart's access
logs are configured per-server-block and only log completed HTTP requests,
these handshake failures are invisible — there is currently no way to
diagnose expired/untrusted/missing client certs from the gateway's logs.

Caddy's standard library TLS/HTTP server surfaces these handshake errors
through its `http.stdlib` logger, but that logger only emits when the
global Caddy `debug` option is enabled (this is a global-options directive,
distinct from the existing `authn.clientCa.debug` sub-directive, which only
tunes verbosity of the `client_ca` auth plugin's own token-issuance logic).

## Goal

Allow operators to enable global Caddy `debug` (and thus TLS handshake
error logging) without also causing every successful HTTP request to be
logged at debug verbosity.

## Design

Add a conditional `debug` directive to the global options block in
`config/Caddyfile`, gated on:

```
{{- if or (eq .Values.log.level "debug") .Values.authn.clientCa.debug }}
  debug
{{- end }}
```

i.e. global Caddy debug turns on when either:
- `log.level` is explicitly set to `debug` (existing knob, already governs
  per-server access log verbosity), or
- `authn.clientCa.debug` is `true` (existing knob, already exists in
  `values.yaml` today, currently only wired into the `client_ca` plugin's
  own debug sub-directive)

No new values.yaml keys are introduced.

### Why this does not log successful requests

Each server block (`:8080`, `:8443`) already declares its own named
access-log logger with an explicit level:

```
log {
  output stdout
  level {{ .Values.log.level }}
  ...
}
```

Caddy's global `debug` option only lowers the level of Caddy's *default*
logger and unlocks stdlib-sourced log lines (`http.stdlib`). It does not
override a logger that already has an explicit `level` set. Since the
`http.stdlib` logger only ever emits on TLS/handshake-level errors (there is
no "successful handshake" log line to suppress), turning on global `debug`
surfaces only the error case the issue asks for — access-log verbosity for
ordinary requests remains governed independently by `log.level`.

### Files touched

- `config/Caddyfile` — add the conditional `debug` line to the global
  options block.
- `values.yaml` — update the comment on `authn.clientCa.debug` to note it
  now also toggles global TLS handshake error logging.
- `README.md` — regenerated via `helm-docs` (existing CI automation already
  regenerates this on chart changes).

### Testing

No existing automated Caddyfile-rendering tests exist in this chart. Verify
via `helm template`:
1. Default values (`clientCa.debug=false`, `log.level=error`) → global
   options block has no `debug` line.
2. `authn.clientCa.debug=true` → global options block includes `debug`.
3. `log.level=debug` → global options block includes `debug`.

Manually inspect rendered output for all three cases; no code changes
needed beyond the Caddyfile template.

## Out of scope

- A dedicated new `log.caddyDebug` toggle (issue's alternative proposal) —
  reusing the existing `authn.clientCa.debug` flag avoids adding another
  knob for the same purpose.
- Extending the same trigger to `authn.spiffe.debug` — not requested by the
  issue; can be added later if SPIFFE mTLS troubleshooting needs the same
  treatment.
