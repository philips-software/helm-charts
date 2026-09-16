# Design: Close the Grafana Org-creation gap via Tenant.organizationRef

## Problem

`provider-orgmapper`'s `Tenant` managed resource only ever writes the
`org_mapping` string into Grafana's `generic_oauth` SSO settings
(`internal/grafana/sso.go: SyncOrgMapping`). It never creates the Grafana Org
itself — `Spec.ForProvider.OrgID` is treated as an opaque, already-existing
identifier. This is a regression relative to the older `tenant-mapper`
service (`HSP_PS_ManagedObservability/Source/tenant-mapper`), which created
the Grafana Org (`Orgs.CreateOrg`) as part of tenant onboarding before it was
replaced by the Crossplane-based stack.

Separately, `provider-gf` (the sibling Crossplane provider already deployed
alongside `provider-orgmapper`, also maintained by the same author) already
has a fully-implemented `Organization` managed resource
(`apis/oss/v1alpha1/organization_types.go`,
`internal/controller/organization/organization.go`) that creates, updates,
and deletes Grafana orgs, including admin/editor/viewer user role
management. It exposes the Grafana-assigned numeric org ID at
`status.atProvider.id`.

The design spec at `2026-07-29-org-mapping-resolver-design.md` (`ResolveOrgIDs`)
is unrelated to this gap — it resolves which org IDs an OIDC claim's groups
grant access to, given an existing `org_mapping` string. It does not create
orgs and explicitly says it isn't wired into the Tenant reconcile loop.

## Decision

Compose with `provider-gf`'s existing `Organization` resource rather than
duplicating Grafana Org lifecycle logic inside `provider-orgmapper`. Add an
optional cross-provider reference field to `Tenant` so its controller can
resolve a `provider-gf`-managed `Organization`'s Grafana-assigned ID at
reconcile time, instead of requiring the caller to already know it.

This avoids a Go build dependency on `provider-gf`: the reference is resolved
via `sigs.k8s.io/controller-runtime`'s generic `client.Client` against
`unstructured.Unstructured`, using a hardcoded GVK
(`oss.gf.m.crossplane.io/v1alpha1`, `Kind: Organization`) and reading
`status.atProvider.id`. This is the standard Crossplane pattern for one
provider's controller observing another provider's CR — a soft contract on
GVK + JSON field path (backed by the CRD), not a compile-time dependency.

### Alternatives considered

- **Duplicate org-creation logic into `provider-orgmapper`** (mirroring
  `tenant-mapper`): rejected — duplicates lifecycle logic (create/update/
  delete, drift, rollback) that already exists and is tested in
  `provider-gf`.
- **Crossplane Composition/XRD** composing `Organization` + `Tenant` with a
  patch carrying the org's resolved ID through the composite: technically
  viable and requires zero Go changes, but introduces a new abstraction
  (XRD + Composition + Claim/XR) that this stack doesn't use today, where
  `Tenant`/`Organization`/`DataSource` are all rendered directly. Rejected
  in favor of keeping the chart's existing "render plain CRs directly"
  model.

## Scope

### 1. Tenant CRD changes (`apis/tenant/v1alpha1/tenant_types.go`)

- `TenantParameters.OrgID` becomes optional (was required).
- New optional `OrganizationRef *OrganizationReference` where
  `OrganizationReference struct { Name string }` — references a
  `provider-gf` `Organization` object in the **same namespace** as the
  `Tenant`.
- New optional `DisplayName string` — a pass-through value the controller
  does not act on directly, but mirrors into status. It exists so the Helm
  chart (or anything else creating the paired `Organization` CR) can source
  the Grafana-visible org name from the `Tenant` spec, decoupled from the
  `Tenant`'s own `metadata.name`/`tenantId` (which stay k8s-safe slugs).
- Validation: **exactly one** of `OrgID` / `OrganizationRef` must be set.
  Enforced in the controller with a new error constant (same style as the
  existing `errDuplicateTenant`), not CRD-level CEL — the repo doesn't use
  `+kubebuilder:validation:XValidation` today.
- `TenantObservation.OrgID` always holds the **resolved** numeric-as-string
  ID regardless of which mode was used. Add `TenantObservation.DisplayName`.

### 2. Resolution mechanism (new `internal/grafana/orgref.go`)

```go
// ResolveOrganizationID fetches a provider-gf Organization by name in the
// given namespace and returns its Grafana-assigned org ID from
// status.atProvider.id. Returns a retryable error if the Organization
// doesn't exist yet or hasn't been assigned an ID yet.
func ResolveOrganizationID(ctx context.Context, kube client.Client, namespace, name string) (string, error)
```

- GVK is a package-level constant, not user-configurable.
- Not found → retryable "not ready" error (wraps `apierrors.IsNotFound`).
- Found but `status.atProvider.id` unset/zero → also retryable "not ready".
- Both cases bubble up as a normal reconcile error; crossplane-runtime's
  existing poll/backoff handles retry — no new retry machinery needed.

### 3. Controller wiring (`internal/controller/tenant/tenant.go`)

- New `resolveOrgID(ctx, cr) (string, error)`: returns
  `cr.Spec.ForProvider.OrgID` directly if set, else resolves the ref via
  `grafana.ResolveOrganizationID`.
- `syncGrafanaOrgMapping`'s loop over *all* tenants (`tenant.go:306-319`)
  currently reads `t.Spec.ForProvider.OrgID` directly for every tenant in
  the list. It must resolve each tenant's *effective* ID instead. If some
  other tenant's ref isn't resolvable yet, skip that tenant from the mapping
  (log at info/debug) rather than failing the whole sync — consistent with
  the existing best-effort posture of `Update`/`Delete`.
- The tenant actually being reconciled (`cr`) is treated more strictly:
  - `Create`: if `cr`'s own ref doesn't resolve, `Create` fails (matches
    today's "Grafana sync must succeed for Create" contract at
    `tenant.go:253-257`).
  - `Update`/`Delete`: stay best-effort, matching existing behavior.
- `isUpToDate` (`tenant.go:392-418`) and `isGrafanaDrifted`
  (`tenant.go:352-375`) currently compare `spec.OrgID` vs `status.OrgID`
  directly. In ref mode `spec.OrgID` is empty by design, so both must
  compare against the *resolved* ID instead. `isGrafanaDrifted` already
  performs a live call during `Observe` (`GetProviderSettings`), so adding
  the ref resolution there extends an existing I/O pattern rather than
  introducing a new one.

### 4. Helm chart wiring (`charts/grafana/templates/tenants.yaml`, new `organizations.yaml`)

- New optional per-tenant value:
  ```yaml
  organization:
    name: <Organization CR name, defaults to "<tenant-name>-org">
    displayName: <Grafana-visible org name>
    admins: []
    editors: []
    viewers: []
    createUsers: false
  ```
- When `.organization` is set: render an `Organization` CR (provider-gf,
  `oss.gf.m.crossplane.io/v1alpha1`) and point
  `Tenant.spec.forProvider.organizationRef.name` at it; do not set `orgId`.
  Set `Tenant.spec.forProvider.displayName` from `.organization.displayName`.
- When `.organization` is absent: unchanged today's behavior (literal
  `.orgId`), no `Organization` CR rendered.
- Template-time `fail` if a tenant sets both `orgId` and `organization`, or
  neither.
- Template-time `fail` if `crossplaneProviders.gf.enabled` is `false` but
  any tenant sets `.organization`.
- `Organization` CRs get an earlier `argocd.argoproj.io/sync-wave` than
  `Tenant` (e.g. `"4"` vs `Tenant`'s `"5"`) — not required for correctness
  (the Tenant controller retries regardless of apply order) but avoids
  noisy not-ready churn on first apply.

### 5. Explicit non-goals

- No folder/dashboard/datasource auto-provisioning into the new org — that
  was extra scope in the old `tenant-mapper` service and is out of scope
  here.
- `Tenant` deletion never deletes the `Organization` — org lifecycle stays
  fully owned by `provider-gf`'s own controller. This is intentionally
  safer than `tenant-mapper`'s old behavior (which deleted the Grafana org
  whenever a tenant was deleted).
- No changes to `provider-gf` itself.
- No Crossplane Composition/XRD layer (see Alternatives above).

## Testing

- `internal/grafana`: table-driven tests for `ResolveOrganizationID` —
  found+ready, not found, found-but-not-ready (zero/missing `id`), malformed
  `status` shape.
- `internal/controller/tenant`: extend `tenant_test.go` for the ref path
  (fake client seeded with an `unstructured.Unstructured` `Organization`),
  the mutual-exclusivity validation error, and `isUpToDate`/drift checks in
  ref mode.
- Regenerate CRDs/deepcopy via `controller-gen` for the new fields; update
  `README.md`'s Tenant field table.

## Rollout

- Ship as a `provider-orgmapper` minor version bump (new optional fields,
  fully backward compatible — existing `Tenant` resources using only
  `orgId` are unaffected).
- Bump `crossplaneProviders.orgmapper.tag`/`package.version` in the Helm
  chart once released; add the `organizations.yaml` template and
  `tenants.yaml` changes in the same chart version bump.
