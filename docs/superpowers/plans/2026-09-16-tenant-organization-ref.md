# Tenant organizationRef Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a `Tenant` resolve its Grafana org ID at runtime from a `provider-gf` `Organization` CR instead of requiring the caller to already know the numeric ID.

**Architecture:** Add an optional `organizationRef` field to `Tenant` alongside the existing literal `orgId`. A new `internal/grafana` helper resolves the ref via an unstructured `client.Client.Get` against a hardcoded `provider-gf` GVK (no Go dependency on provider-gf). The Tenant controller uses the resolved ID everywhere it currently uses `Spec.ForProvider.OrgID` directly.

**Tech Stack:** Go, controller-runtime, crossplane-runtime v2, controller-gen.

**Spec:** `docs/superpowers/specs/2026-09-16-tenant-organization-ref-design.md`

## Global Constraints

- Exactly one of `orgId` / `organizationRef` must be set on a `Tenant` — enforced in the controller, not CRD-level CEL.
- No Go module dependency on `provider-gf` — resolve via `unstructured.Unstructured` + a hardcoded GVK constant (`oss.gf.m.crossplane.io/v1alpha1`, `Kind: Organization`).
- `Tenant` deletion must never delete the referenced `Organization`.
- Existing `Tenant` resources using only literal `orgId` must keep working unchanged (backward compatible).

---

### Task 1: Tenant CRD fields (`OrganizationRef`, `DisplayName`, optional `OrgID`)

**Files:**
- Modify: `apis/tenant/v1alpha1/tenant_types.go`
- Regenerate: `apis/tenant/v1alpha1/zz_generated.deepcopy.go`, `package/crds/tenant.orgmapper.m.crossplane.io_tenants.yaml`

**Interfaces:**
- Produces: `v1alpha1.OrganizationReference{Name string}`, `v1alpha1.TenantParameters.OrganizationRef *OrganizationReference`, `v1alpha1.TenantParameters.DisplayName string`, `v1alpha1.TenantObservation.DisplayName string`. `TenantParameters.OrgID` changes from required to optional (kubebuilder marker only, type stays `string`).

- [ ] **Step 1: Edit `TenantParameters` in `apis/tenant/v1alpha1/tenant_types.go`**

Replace the `OrgID` field's validation marker and add the two new fields, right after the `OrgID` field:

```go
	// OrgID is the mapped organization identifier. Exactly one of OrgID or
	// OrganizationRef must be set.
	// +optional
	OrgID string `json:"orgId,omitempty"`

	// OrganizationRef references a provider-gf Organization in the same
	// namespace whose Grafana-assigned org ID should be used. Exactly one
	// of OrgID or OrganizationRef must be set.
	// +optional
	OrganizationRef *OrganizationReference `json:"organizationRef,omitempty"`

	// DisplayName is a human-readable name for the tenant's Grafana org.
	// Not acted on directly by this controller; it exists so callers (e.g.
	// the Helm chart) can source the paired Organization's display name
	// from the Tenant spec.
	// +optional
	DisplayName string `json:"displayName,omitempty"`
```

Remove the old `OrgID` field block (the one with `+kubebuilder:validation:Required` and `+kubebuilder:validation:MinLength=1`) — it's replaced by the block above.

Add the `OrganizationReference` type below `RetentionPolicy`:

```go
// OrganizationReference identifies a provider-gf Organization managed
// resource by name, in the same namespace as the referencing Tenant.
type OrganizationReference struct {
	// Name is the name of the Organization managed resource.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Name string `json:"name"`
}
```

Add `DisplayName` to `TenantObservation`, right after `OrgID`:

```go
	OrgID       string `json:"orgId,omitempty"`
	DisplayName string `json:"displayName,omitempty"`
```

(This replaces the existing `OrgID string \`json:"orgId,omitempty"\`` line in `TenantObservation` — just add the `DisplayName` line after it.)

- [ ] **Step 2: Regenerate deepcopy and CRD YAML**

Run:
```bash
cd /Users/andy/DEV/Personal/provider-orgmapper/apis && go run -tags generate sigs.k8s.io/controller-tools/cmd/controller-gen object:headerFile=../hack/boilerplate.go.txt paths=./tenant/... crd:crdVersions=v1 output:artifacts:config=../package/crds
```
Expected: exits 0, `zz_generated.deepcopy.go` gains a `DeepCopyInto`/`DeepCopy` pair for `OrganizationReference` and `TenantParameters.DeepCopyInto` gains a nil-check block for `OrganizationRef`, and `package/crds/tenant.orgmapper.m.crossplane.io_tenants.yaml` gains the new fields.

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go build ./...`
Expected: exits 0.

- [ ] **Step 4: Run existing tests to confirm no regression**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./apis/... ./internal/controller/tenant/...`
Expected: all PASS (no behavior changed yet, just schema).

- [ ] **Step 5: Commit**

```bash
git add apis/tenant/v1alpha1/tenant_types.go apis/tenant/v1alpha1/zz_generated.deepcopy.go package/crds/tenant.orgmapper.m.crossplane.io_tenants.yaml
git commit -m "feat(tenant): add organizationRef and displayName fields"
```

---

### Task 2: `ResolveOrganizationID` resolver

**Files:**
- Create: `internal/grafana/orgref.go`
- Test: `internal/grafana/orgref_test.go`

**Interfaces:**
- Consumes: `sigs.k8s.io/controller-runtime/pkg/client.Client`, `k8s.io/apimachinery/pkg/apis/meta/v1/unstructured.Unstructured`.
- Produces: `func ResolveOrganizationID(ctx context.Context, kube client.Client, namespace, name string) (string, error)`.

- [ ] **Step 1: Write the failing test**

```go
// internal/grafana/orgref_test.go
package grafana

import (
	"context"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	clfake "sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func newOrgScheme() *runtime.Scheme {
	scheme := runtime.NewScheme()
	scheme.AddKnownTypeWithName(organizationGVK, &unstructured.Unstructured{})
	scheme.AddKnownTypeWithName(organizationGVK.GroupVersion().WithKind("OrganizationList"), &unstructured.UnstructuredList{})
	return scheme
}

func newOrg(namespace, name string, id any) *unstructured.Unstructured {
	u := &unstructured.Unstructured{}
	u.SetGroupVersionKind(organizationGVK)
	u.SetNamespace(namespace)
	u.SetName(name)
	if id != nil {
		_ = unstructured.SetNestedField(u.Object, id, "status", "atProvider", "id")
	}
	return u
}

func TestResolveOrganizationID(t *testing.T) {
	ctx := context.Background()

	t.Run("ready with int64 id", func(t *testing.T) {
		kube := clfake.NewClientBuilder().WithScheme(newOrgScheme()).WithObjects(newOrg("ns1", "acme-org", int64(42))).Build()
		got, err := ResolveOrganizationID(ctx, kube, "ns1", "acme-org")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "42" {
			t.Errorf("got %q, want %q", got, "42")
		}
	})

	t.Run("ready with float64 id", func(t *testing.T) {
		kube := clfake.NewClientBuilder().WithScheme(newOrgScheme()).WithObjects(newOrg("ns1", "acme-org", float64(7))).Build()
		got, err := ResolveOrganizationID(ctx, kube, "ns1", "acme-org")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "7" {
			t.Errorf("got %q, want %q", got, "7")
		}
	})

	t.Run("not found", func(t *testing.T) {
		kube := clfake.NewClientBuilder().WithScheme(newOrgScheme()).Build()
		_, err := ResolveOrganizationID(ctx, kube, "ns1", "missing-org")
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("found but not ready", func(t *testing.T) {
		kube := clfake.NewClientBuilder().WithScheme(newOrgScheme()).WithObjects(newOrg("ns1", "acme-org", nil)).Build()
		_, err := ResolveOrganizationID(ctx, kube, "ns1", "acme-org")
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("id is zero", func(t *testing.T) {
		kube := clfake.NewClientBuilder().WithScheme(newOrgScheme()).WithObjects(newOrg("ns1", "acme-org", int64(0))).Build()
		_, err := ResolveOrganizationID(ctx, kube, "ns1", "acme-org")
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

var _ = schema.GroupVersionKind{} // keep schema import if unused by later edits
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/grafana/... -run TestResolveOrganizationID -v`
Expected: FAIL — `organizationGVK` and `ResolveOrganizationID` undefined.

- [ ] **Step 3: Write the implementation**

```go
// internal/grafana/orgref.go
package grafana

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// organizationGVK identifies the provider-gf Organization managed resource.
// This is a soft contract on provider-gf's CRD, not a Go dependency on it.
var organizationGVK = schema.GroupVersionKind{
	Group:   "oss.gf.m.crossplane.io",
	Version: "v1alpha1",
	Kind:    "Organization",
}

// ResolveOrganizationID fetches a provider-gf Organization by name in the
// given namespace and returns its Grafana-assigned org ID from
// status.atProvider.id, as a string. Returns an error if the Organization
// doesn't exist yet, or exists but hasn't been assigned an ID yet -both
// are treated as retryable by callers via the normal reconcile error path.
func ResolveOrganizationID(ctx context.Context, kube client.Client, namespace, name string) (string, error) {
	u := &unstructured.Unstructured{}
	u.SetGroupVersionKind(organizationGVK)

	if err := kube.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, u); err != nil {
		if apierrors.IsNotFound(err) {
			return "", fmt.Errorf("organization %q not found in namespace %q: %w", name, namespace, err)
		}
		return "", fmt.Errorf("cannot get organization %q: %w", name, err)
	}

	val, found, err := unstructured.NestedFieldNoCopy(u.Object, "status", "atProvider", "id")
	if err != nil {
		return "", fmt.Errorf("organization %q has malformed status: %w", name, err)
	}
	if !found {
		return "", fmt.Errorf("organization %q has no status.atProvider.id yet", name)
	}

	var id int64
	switch v := val.(type) {
	case int64:
		id = v
	case float64:
		id = int64(v)
	default:
		return "", fmt.Errorf("organization %q status.atProvider.id has unexpected type %T", name, val)
	}
	if id == 0 {
		return "", fmt.Errorf("organization %q has not been assigned an id yet", name)
	}

	return fmt.Sprintf("%d", id), nil
}
```

- [ ] **Step 4: Remove the throwaway `var _ = schema...` line from the test file**

It was only needed to keep the `schema` import valid before the implementation existed; the implementation now uses `schema.GroupVersionKind` directly via `organizationGVK`, and the test itself uses `schema` for `organizationGVK.GroupVersion().WithKind(...)`. Delete the `var _ = schema.GroupVersionKind{}` line and its comment from `internal/grafana/orgref_test.go`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/grafana/... -run TestResolveOrganizationID -v`
Expected: all 5 subtests PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/grafana/orgref.go internal/grafana/orgref_test.go
git commit -m "feat(grafana): add ResolveOrganizationID for provider-gf Organization refs"
```

---

### Task 3: `resolveOrgID` on the Tenant controller + mutual-exclusivity validation

**Files:**
- Modify: `internal/controller/tenant/tenant.go`
- Test: `internal/controller/tenant/tenant_test.go`

**Interfaces:**
- Consumes: `grafana.ResolveOrganizationID(ctx, kube, namespace, name) (string, error)` (Task 2).
- Produces: `func (c *external) resolveOrgID(ctx context.Context, cr *v1alpha1.Tenant) (string, error)`, error constants `errOrgIDConflict`, `errOrgIDMissing`.

- [ ] **Step 1: Write the failing tests**

Add to `internal/controller/tenant/tenant_test.go` (new test function, place after `TestCreate`):

```go
func TestResolveOrgID(t *testing.T) {
	ctx := context.Background()

	t.Run("literal orgId wins when set", func(t *testing.T) {
		cr := tenantWithSpec("acme", "org-1", nil, v1alpha1.RetentionPolicy{})
		e := external{kube: newFakeKube(), logger: logging.NewNopLogger()}
		got, err := e.resolveOrgID(ctx, cr)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "org-1" {
			t.Errorf("got %q, want %q", got, "org-1")
		}
	})

	t.Run("both orgId and organizationRef set is an error", func(t *testing.T) {
		cr := tenantWithSpec("acme", "org-1", nil, v1alpha1.RetentionPolicy{})
		cr.Spec.ForProvider.OrganizationRef = &v1alpha1.OrganizationReference{Name: "acme-org"}
		e := external{kube: newFakeKube(), logger: logging.NewNopLogger()}
		_, err := e.resolveOrgID(ctx, cr)
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("neither orgId nor organizationRef set is an error", func(t *testing.T) {
		cr := tenantWithSpec("acme", "", nil, v1alpha1.RetentionPolicy{})
		e := external{kube: newFakeKube(), logger: logging.NewNopLogger()}
		_, err := e.resolveOrgID(ctx, cr)
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("organizationRef not resolvable is an error", func(t *testing.T) {
		cr := tenantWithSpec("acme", "", nil, v1alpha1.RetentionPolicy{})
		cr.Spec.ForProvider.OrganizationRef = &v1alpha1.OrganizationReference{Name: "acme-org"}
		e := external{kube: newFakeKube(), logger: logging.NewNopLogger()}
		_, err := e.resolveOrgID(ctx, cr)
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -run TestResolveOrgID -v`
Expected: FAIL to compile — `e.resolveOrgID` and `v1alpha1.OrganizationReference` (the latter already exists from Task 1) undefined.

- [ ] **Step 3: Add error constants and `resolveOrgID`**

In `internal/controller/tenant/tenant.go`, add to the `const` block (around line 45-53):

```go
	errOrgIDConflict  = "exactly one of orgId or organizationRef must be set, not both"
	errOrgIDMissing   = "exactly one of orgId or organizationRef must be set"
	errResolveOrgID   = "cannot resolve organization id"
```

Add the new method, placed right after `Connect` (around line 137, before `extractConfig`):

```go
// resolveOrgID returns the effective Grafana org ID for cr: the literal
// OrgID if set, otherwise the ID resolved from OrganizationRef. Exactly one
// of the two must be set.
func (c *external) resolveOrgID(ctx context.Context, cr *v1alpha1.Tenant) (string, error) {
	hasLiteral := cr.Spec.ForProvider.OrgID != ""
	hasRef := cr.Spec.ForProvider.OrganizationRef != nil

	if hasLiteral && hasRef {
		return "", errors.New(errOrgIDConflict)
	}
	if !hasLiteral && !hasRef {
		return "", errors.New(errOrgIDMissing)
	}
	if hasLiteral {
		return cr.Spec.ForProvider.OrgID, nil
	}

	id, err := grafana.ResolveOrganizationID(ctx, c.kube, cr.GetNamespace(), cr.Spec.ForProvider.OrganizationRef.Name)
	if err != nil {
		return "", errors.Wrap(err, errResolveOrgID)
	}
	return id, nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -run TestResolveOrgID -v`
Expected: all 4 subtests PASS.

- [ ] **Step 5: Run the full package test suite to confirm no regression**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -v`
Expected: all PASS (this method isn't wired into `Create`/`Update`/`Observe` yet, so no existing behavior changes).

- [ ] **Step 6: Commit**

```bash
git add internal/controller/tenant/tenant.go internal/controller/tenant/tenant_test.go
git commit -m "feat(tenant): add resolveOrgID with orgId/organizationRef mutual exclusivity"
```

---

### Task 4: Wire `resolveOrgID` into `Create`, `syncStatus`, and `syncGrafanaOrgMapping`

**Files:**
- Modify: `internal/controller/tenant/tenant.go`
- Test: `internal/controller/tenant/tenant_test.go`

**Interfaces:**
- Consumes: `c.resolveOrgID(ctx, cr) (string, error)` (Task 3).
- Produces: `syncStatus` gains a `resolvedOrgID string` parameter; `syncGrafanaOrgMapping` resolves each listed tenant's effective ID individually and skips ones that don't resolve.

- [ ] **Step 1: Write the failing test**

Add to `internal/controller/tenant/tenant_test.go`, a new case exercising the ref path end-to-end through `Create`. First add a helper next to `tenantWithSpec`:

```go
func tenantWithRef(tenantID, orgName string, retention v1alpha1.RetentionPolicy) *v1alpha1.Tenant {
	t := &v1alpha1.Tenant{}
	t.Spec.ForProvider = v1alpha1.TenantParameters{
		TenantID:        tenantID,
		OrganizationRef: &v1alpha1.OrganizationReference{Name: orgName},
		Retention:       retention,
	}
	return t
}
```

Add a new subtest to the `cases` map inside `TestCreate` (after `"DuplicateTenantID"`):

```go
		"OrganizationRefResolved": {
			reason: "Should resolve organizationRef and use it as the effective orgId.",
			kube: func() client.Client {
				scheme := runtime.NewScheme()
				_ = v1alpha1.SchemeBuilder.AddToScheme(scheme)
				scheme.AddKnownTypeWithName(
					schema.GroupVersionKind{Group: "oss.gf.m.crossplane.io", Version: "v1alpha1", Kind: "Organization"},
					&unstructured.Unstructured{},
				)
				org := &unstructured.Unstructured{}
				org.SetGroupVersionKind(schema.GroupVersionKind{Group: "oss.gf.m.crossplane.io", Version: "v1alpha1", Kind: "Organization"})
				org.SetName("acme-org")
				_ = unstructured.SetNestedField(org.Object, int64(99), "status", "atProvider", "id")
				return clfake.NewClientBuilder().WithScheme(scheme).WithObjects(org).Build()
			}(),
			sso: defaultMockSSO(),
			args: args{
				ctx: context.Background(),
				mg:  tenantWithRef("acme", "acme-org", retention),
			},
			want: want{
				o: managed.ExternalCreation{},
			},
		},
```

Add these imports to `internal/controller/tenant/tenant_test.go`: `"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"` and `"k8s.io/apimachinery/pkg/runtime/schema"`.

Then extend the post-`Create` assertion block (the `if err == nil { ... }` block at the end of `TestCreate`'s loop) to check the resolved ID landed in status:

```go
					if cr.Spec.ForProvider.OrganizationRef != nil && cr.Status.AtProvider.OrgID != "99" {
						t.Errorf("\n%s\ne.Create(...): expected status orgId %q, got %q", tc.reason, "99", cr.Status.AtProvider.OrgID)
					}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -run TestCreate -v`
Expected: FAIL — `cr.Status.AtProvider.OrgID` is `""` (empty), because `Create` still writes `cr.Spec.ForProvider.OrgID` verbatim via `syncStatus`, and that field is empty in ref mode.

- [ ] **Step 3: Change `syncStatus` to take the resolved ID, and wire `resolveOrgID` into `Create`**

Replace `syncStatus`'s signature and body (currently at `tenant.go:378-389`):

```go
// syncStatus copies spec fields into status and sets the lastUpdated timestamp.
// resolvedOrgID is the effective org ID (literal or resolved from a ref).
func syncStatus(cr *v1alpha1.Tenant, resolvedOrgID string) {
	cr.Status.AtProvider = v1alpha1.TenantObservation{
		TenantID:     cr.Spec.ForProvider.TenantID,
		OrgID:        resolvedOrgID,
		DisplayName:  cr.Spec.ForProvider.DisplayName,
		Admins:       cr.Spec.ForProvider.Admins,
		ViewerGroups: cr.Spec.ForProvider.ViewerGroups,
		EditorGroups: cr.Spec.ForProvider.EditorGroups,
		AdminGroups:  cr.Spec.ForProvider.AdminGroups,
		Retention:    cr.Spec.ForProvider.Retention,
		LastUpdated:  time.Now().UTC().Format(time.RFC3339),
	}
}
```

Update `Create` (currently `tenant.go:239-260`) to resolve before calling `syncStatus`:

```go
func (c *external) Create(ctx context.Context, mg resource.Managed) (managed.ExternalCreation, error) {
	cr, ok := mg.(*v1alpha1.Tenant)
	if !ok {
		return managed.ExternalCreation{}, errors.New(errNotTenant)
	}

	if err := c.validateUniqueTenantID(ctx, cr); err != nil {
		return managed.ExternalCreation{}, err
	}

	orgID, err := c.resolveOrgID(ctx, cr)
	if err != nil {
		return managed.ExternalCreation{}, err
	}

	meta.SetExternalName(cr, cr.Spec.ForProvider.TenantID)
	syncStatus(cr, orgID)

	if err := c.syncGrafanaOrgMapping(ctx, cr, false); err != nil {
		return managed.ExternalCreation{}, err
	}

	return managed.ExternalCreation{}, nil
}
```

Update `Update` (currently `tenant.go:262-277`) the same way, but best-effort per the existing posture — a resolution failure is logged, not returned:

```go
func (c *external) Update(ctx context.Context, mg resource.Managed) (managed.ExternalUpdate, error) {
	cr, ok := mg.(*v1alpha1.Tenant)
	if !ok {
		return managed.ExternalUpdate{}, errors.New(errNotTenant)
	}

	orgID, err := c.resolveOrgID(ctx, cr)
	if err != nil {
		c.logger.Info("Failed to resolve organization id", "error", err)
		orgID = cr.Status.AtProvider.OrgID // keep last known value
	}
	syncStatus(cr, orgID)

	if err := c.syncGrafanaOrgMapping(ctx, cr, false); err != nil {
		c.logger.Info("Failed to sync Grafana org mapping", "error", err)
	}

	return managed.ExternalUpdate{}, nil
}
```

- [ ] **Step 4: Update `syncGrafanaOrgMapping`'s tenant-list loop to resolve each tenant's effective ID**

Replace the loop body in `syncGrafanaOrgMapping` (currently `tenant.go:306-319`):

```go
	mappings := make([]grafana.TenantMapping, 0, len(list.Items))
	for i := range list.Items {
		t := &list.Items[i]
		if deleting && t.GetUID() == cr.GetUID() {
			continue
		}
		orgID, err := c.resolveOrgID(ctx, t)
		if err != nil {
			c.logger.Debug("Skipping tenant with unresolved org id", "tenant", t.GetName(), "error", err)
			continue
		}
		mappings = append(mappings, grafana.TenantMapping{
			OrgID:        orgID,
			ViewerGroups: t.Spec.ForProvider.ViewerGroups,
			EditorGroups: t.Spec.ForProvider.EditorGroups,
			AdminGroups:  t.Spec.ForProvider.AdminGroups,
		})
	}
```

- [ ] **Step 5: Fix the other two `syncStatus` call sites**

`Delete` doesn't call `syncStatus`, so no change there. Search for any remaining bare `syncStatus(cr)` calls:

Run: `grep -n "syncStatus(" /Users/andy/DEV/Personal/provider-orgmapper/internal/controller/tenant/tenant.go`
Expected: only the two call sites just edited (in `Create` and `Update`) remain, both now passing `orgID`.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -run TestCreate -v`
Expected: all subtests PASS, including `OrganizationRefResolved`.

- [ ] **Step 7: Run the full package test suite**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -v`
Expected: `TestUpdate`'s existing assertion `cr.Status.AtProvider.OrgID != cr.Spec.ForProvider.OrgID` (tenant_test.go:408-410) still passes because that test only uses literal `orgId` (`tenantWithSpec`), so `resolveOrgID` returns the literal value unchanged — no update needed there. All other existing tests PASS.

- [ ] **Step 8: Commit**

```bash
git add internal/controller/tenant/tenant.go internal/controller/tenant/tenant_test.go
git commit -m "feat(tenant): resolve organizationRef in Create/Update/syncGrafanaOrgMapping"
```

---

### Task 5: Make `Observe`/`isUpToDate`/`isGrafanaDrifted` compare against the resolved ID

**Files:**
- Modify: `internal/controller/tenant/tenant.go`
- Test: `internal/controller/tenant/tenant_test.go`

**Interfaces:**
- Produces: `func isUpToDate(cr *v1alpha1.Tenant, resolvedOrgID string) bool` (signature change, was `isUpToDate(cr)`); `func (c *external) isGrafanaDrifted(cr *v1alpha1.Tenant, resolvedOrgID string) (bool, error)` (signature change, was `isGrafanaDrifted(cr)`).

- [ ] **Step 1: Update existing call sites in the test file first (so the compile error is the only failure)**

In `internal/controller/tenant/tenant_test.go`:
- In `TestIsUpToDate`, change every `got := isUpToDate(tc.cr)` to `got := isUpToDate(tc.cr, tc.cr.Spec.ForProvider.OrgID)` (all existing cases use literal `orgId`, so passing it straight through preserves current behavior).

- [ ] **Step 2: Add a failing test for ref-mode drift detection**

Add to `TestObserve`'s `cases` map (after `"GrafanaDriftDetected"`):

```go
		"OrganizationRefNotYetResolvable": {
			reason: "Should return ResourceUpToDate false when organizationRef can't be resolved yet.",
			sso:    defaultMockSSO(),
			args: args{
				ctx: context.Background(),
				mg: func() resource.Managed {
					cr := tenantWithRef("acme", "acme-org", retention)
					meta.SetExternalName(cr, "acme")
					cr.Status.AtProvider = v1alpha1.TenantObservation{
						TenantID:    "acme",
						Retention:   retention,
						LastUpdated: "2025-01-01T00:00:00Z",
					}
					return cr
				}(),
			},
			want: want{
				o: managed.ExternalObservation{ResourceExists: true, ResourceUpToDate: false},
			},
		},
```

This case has no `kube` set on `tc.sso`/`external{}` in the test loop (`e := external{sso: tc.sso, logger: ...}`, no `kube`), so resolving the ref will fail with a nil-client error — which is exactly the "not yet resolvable" path this test is checking.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -run 'TestIsUpToDate|TestObserve' -v`
Expected: compile FAIL on `isUpToDate(tc.cr, tc.cr.Spec.ForProvider.OrgID)` (too many args to current 1-arg signature) and on `tenantWithRef` (doesn't exist yet in this file if Task 4 wasn't merged first — it was added in Task 4, so this should already compile; the actual failure is the `isUpToDate` arity mismatch).

- [ ] **Step 4: Change `isUpToDate`'s signature and body**

Replace (currently `tenant.go:392-418`):

```go
// isUpToDate compares spec.ForProvider against status.atProvider, using
// resolvedOrgID (literal or resolved from organizationRef) in place of
// spec.ForProvider.OrgID, which is empty when organizationRef is used.
func isUpToDate(cr *v1alpha1.Tenant, resolvedOrgID string) bool {
	spec := cr.Spec.ForProvider
	obs := cr.Status.AtProvider

	if spec.TenantID != obs.TenantID {
		return false
	}
	if resolvedOrgID != obs.OrgID {
		return false
	}
	if spec.Retention != obs.Retention {
		return false
	}
	if !slicesEqual(spec.Admins, obs.Admins) {
		return false
	}
	if !slicesEqual(spec.ViewerGroups, obs.ViewerGroups) {
		return false
	}
	if !slicesEqual(spec.EditorGroups, obs.EditorGroups) {
		return false
	}
	if !slicesEqual(spec.AdminGroups, obs.AdminGroups) {
		return false
	}
	return true
}
```

- [ ] **Step 5: Change `isGrafanaDrifted`'s signature and body**

Replace (currently `tenant.go:352-375`):

```go
// isGrafanaDrifted checks whether resolvedOrgID's org_mapping entries are
// present in the Grafana SSO settings. Returns true if missing from the
// mapping.
func (c *external) isGrafanaDrifted(cr *v1alpha1.Tenant, resolvedOrgID string) (bool, error) {
	if len(cr.Spec.ForProvider.ViewerGroups) == 0 && len(cr.Spec.ForProvider.EditorGroups) == 0 && len(cr.Spec.ForProvider.AdminGroups) == 0 {
		return false, nil
	}

	resp, err := c.sso.GetProviderSettings("generic_oauth")
	if err != nil {
		if grafana.IsNotFound(err) {
			return true, nil
		}
		return false, err
	}

	settings, ok := resp.Payload.Settings.(map[string]any)
	if !ok {
		return true, nil
	}

	orgMapping, _ := settings["orgMapping"].(string)
	return !grafana.OrgMappingContains(orgMapping, resolvedOrgID), nil
}
```

- [ ] **Step 6: Update `Observe` to resolve once and pass the result through**

Replace the body of `Observe` from the `upToDate := isUpToDate(cr)` line onward (currently `tenant.go:212-236`):

```go
	orgID, err := c.resolveOrgID(ctx, cr)
	if err != nil {
		c.logger.Debug("Failed to resolve organization id", "error", err)
		return managed.ExternalObservation{
			ResourceExists:   true,
			ResourceUpToDate: false,
		}, nil
	}

	upToDate := isUpToDate(cr, orgID)

	if upToDate {
		cr.SetConditions(xpv1.Available())

		drifted, err := c.isGrafanaDrifted(cr, orgID)
		if err != nil {
			c.logger.Debug("Failed to check Grafana drift", "error", err)
		} else if drifted {
			c.logger.Info("Grafana org_mapping drift detected, triggering resync")
			upToDate = false
		}
	}

	return managed.ExternalObservation{
		ResourceExists:   true,
		ResourceUpToDate: upToDate,
	}, nil
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd /Users/andy/DEV/Personal/provider-orgmapper && go test ./internal/controller/tenant/... -v`
Expected: all PASS, including the new `OrganizationRefNotYetResolvable` case.

- [ ] **Step 8: Commit**

```bash
git add internal/controller/tenant/tenant.go internal/controller/tenant/tenant_test.go
git commit -m "feat(tenant): compare resolved org id in Observe drift/up-to-date checks"
```

---

### Task 6: Helm chart — render paired `Organization` CRs and wire `organizationRef`

**Repo:** `/Users/andy/DEV/Philips/philips-software/helm-charts/charts/grafana` (separate repo from provider-orgmapper).

**Files:**
- Create: `templates/organizations.yaml`
- Modify: `templates/tenants.yaml`

**Interfaces:**
- Consumes: `Tenant.spec.forProvider.organizationRef.name`, `Tenant.spec.forProvider.displayName` (Task 1); provider-gf's `Organization` CRD (`oss.gf.m.crossplane.io/v1alpha1`, fields `spec.forProvider.name/admins/editors/viewers/createUsers`, confirmed at `/Users/andy/DEV/Personal/provider-gf/apis/oss/v1alpha1/organization_types.go`).
- Produces: new per-tenant values contract key `.organization: {name, displayName, admins, editors, viewers, createUsers}`, mutually exclusive with `.orgId`.

- [ ] **Step 1: Update `templates/tenants.yaml`**

Replace the file's contents with:

```yaml
{{- if .Values.crossplaneProviders.orgmapper.enabled }}
{{- $tenants := .Values.tenants | default .Values.grafana.tenants }}
{{- range $tenants }}
{{- if and .orgId .organization }}
{{- fail (printf "tenant %q: set either orgId or organization, not both" .name) }}
{{- end }}
{{- if not (or .orgId .organization) }}
{{- fail (printf "tenant %q: one of orgId or organization is required" .name) }}
{{- end }}
{{- if and .organization (not $.Values.crossplaneProviders.gf.enabled) }}
{{- fail (printf "tenant %q: organization requires crossplaneProviders.gf.enabled=true" .name) }}
{{- end }}
---
apiVersion: tenant.orgmapper.crossplane.io/v1alpha1
kind: Tenant
metadata:
  name: {{ .name }}
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  forProvider:
    tenantId: {{ .tenantId }}
    {{- if .organization }}
    organizationRef:
      name: {{ .organization.name | default (printf "%s-org" .name) }}
    {{- with .organization.displayName }}
    displayName: {{ . | quote }}
    {{- end }}
    {{- else }}
    orgId: {{ .orgId | quote }}
    {{- end }}
    {{- with .viewerGroups }}
    viewerGroups:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .editorGroups }}
    editorGroups:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .adminGroups }}
    adminGroups:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .retention }}
    retention:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  providerConfigRef:
    name: default
    kind: ProviderConfig
{{- end }}
{{- end }}
```

- [ ] **Step 2: Create `templates/organizations.yaml`**

```yaml
{{- if .Values.crossplaneProviders.orgmapper.enabled }}
{{- $tenants := .Values.tenants | default .Values.grafana.tenants }}
{{- range $tenants }}
{{- if .organization }}
---
apiVersion: oss.gf.m.crossplane.io/v1alpha1
kind: Organization
metadata:
  name: {{ .organization.name | default (printf "%s-org" .name) }}
  annotations:
    argocd.argoproj.io/sync-wave: "4"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  forProvider:
    name: {{ .organization.displayName | default .name | quote }}
    {{- with .organization.admins }}
    admins:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .organization.editors }}
    editors:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .organization.viewers }}
    viewers:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if hasKey .organization "createUsers" }}
    createUsers: {{ .organization.createUsers }}
    {{- end }}
  providerConfigRef:
    name: default
    kind: ProviderConfig
{{- end }}
{{- end }}
{{- end }}
```

- [ ] **Step 3: Add a values.yaml comment documenting the new contract**

In `values.yaml`, right after the existing `tenants: []` line under `grafana:` (around line 105), add:

```yaml
  # Each tenant needs exactly one of orgId (existing Grafana org) or
  # organization (auto-create via provider-gf's Organization resource):
  #   - name: my-tenant
  #     tenantId: my-tenant
  #     orgId: "5"                       # OR:
  #     organization:
  #       displayName: "My Tenant"       # Grafana-visible org name
  #       admins: []
  #       editors: []
  #       viewers: []
  tenants: []
```

- [ ] **Step 4: Render and verify with `helm template`**

Run (from the chart directory):
```bash
cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/grafana
helm template test . --set 'tenants[0].name=acme' --set 'tenants[0].tenantId=acme' --set 'tenants[0].organization.displayName=Acme Corp' --show-only templates/organizations.yaml --show-only templates/tenants.yaml
```
Expected: renders one `Organization` named `acme-org` with `spec.forProvider.name: "Acme Corp"`, and one `Tenant` with `spec.forProvider.organizationRef.name: acme-org` and `spec.forProvider.displayName: "Acme Corp"`, no `orgId` field present.

- [ ] **Step 5: Verify the mutual-exclusivity guard fires**

Run:
```bash
helm template test . --set 'tenants[0].name=acme' --set 'tenants[0].tenantId=acme' --set 'tenants[0].orgId=5' --set 'tenants[0].organization.displayName=Acme Corp'
```
Expected: fails with `tenant "acme": set either orgId or organization, not both`.

- [ ] **Step 6: Verify existing literal-orgId tenants still render unchanged**

Run:
```bash
helm template test . --set 'tenants[0].name=acme' --set 'tenants[0].tenantId=acme' --set 'tenants[0].orgId=5' --show-only templates/tenants.yaml
```
Expected: renders the same `Tenant` shape as before this change (`orgId: "5"`, no `organizationRef`), and `templates/organizations.yaml` renders nothing for this tenant.

- [ ] **Step 7: Commit**

```bash
git add templates/organizations.yaml templates/tenants.yaml values.yaml
git commit -m "feat: render provider-gf Organization CRs and wire Tenant.organizationRef"
```

---

### Task 7: Documentation

**Files:**
- Modify: `/Users/andy/DEV/Personal/provider-orgmapper/README.md`
- Modify: `/Users/andy/DEV/Philips/philips-software/helm-charts/charts/grafana/README.md.gotmpl`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the provider-orgmapper Tenant field table**

In `README.md`, find the table row `| \`spec.forProvider.orgId\` | string | Yes | Grafana organization ID |` (around line 266) and replace it with:

```markdown
| `spec.forProvider.orgId` | string | One of orgId/organizationRef | Grafana organization ID (use when the org already exists) |
| `spec.forProvider.organizationRef.name` | string | One of orgId/organizationRef | Name of a provider-gf `Organization` resource to resolve the org ID from |
| `spec.forProvider.displayName` | string | No | Human-readable org name; not acted on directly, passed through to status for callers that create the paired Organization |
```

Add a short subsection after the field table (before the next `##` heading) explaining the two modes:

```markdown
### Org ID resolution

A Tenant needs exactly one of:
- `orgId` — a literal Grafana organization ID, for orgs that already exist.
- `organizationRef.name` — the name of a `provider-gf` `Organization` resource
  (in the same namespace) whose Grafana-assigned ID should be used once
  provider-gf finishes creating it. `provider-orgmapper` does not create
  Grafana orgs itself; it resolves this reference by reading the
  Organization's `status.atProvider.id`.
```

- [ ] **Step 2: Update the chart README template**

In `README.md.gotmpl` (the chart's docs source, from which `README.md` is generated), find the tenant example/values documentation section and add a short paragraph after it:

```markdown
### Auto-creating Grafana orgs

Set `organization` instead of `orgId` on a tenant entry to have this chart
create the Grafana org via provider-gf's `Organization` resource, and wire
the tenant to it automatically:

```yaml
tenants:
  - name: acme
    tenantId: acme
    organization:
      displayName: "Acme Corp"
      admins: []
```

Requires `crossplaneProviders.gf.enabled: true`.
```

- [ ] **Step 3: Regenerate the chart's README.md if the repo uses helm-docs**

Run: `cd /Users/andy/DEV/Philips/philips-software/helm-charts/charts/grafana && helm-docs` (if `helm-docs` isn't installed, skip this step and hand-edit the corresponding section of `README.md` to match `README.md.gotmpl`).

- [ ] **Step 4: Commit**

```bash
# provider-orgmapper repo
git add README.md
git commit -m "docs: document Tenant organizationRef and displayName"

# helm-charts repo
git add README.md.gotmpl README.md
git commit -m "docs: document tenant.organization for auto-creating Grafana orgs"
```

---

## Self-Review Notes

- **Spec coverage:** Section 1 (CRD) → Task 1; Section 2 (resolver) → Task 2; Section 3 (controller wiring, incl. best-effort vs strict resolution) → Tasks 3-5; Section 4 (chart) → Task 6; Section 5 (non-goals) → verified nothing in Tasks 1-6 creates/deletes orgs or provisions folders/dashboards/datasources, and `Tenant`'s `Delete` (unchanged) never touches the `Organization`; Section on testing → a test task is embedded in every code task (TDD steps), not deferred.
- **Type consistency:** `resolveOrgID`/`ResolveOrganizationID`/`isUpToDate`/`isGrafanaDrifted`/`syncStatus` signatures are introduced once (Tasks 2-5) and reused with identical names/types in every later task and test.
- **Cross-repo note:** Tasks 1-5 are in `provider-orgmapper`; Tasks 6-7 touch a second, separate repo (`helm-charts`). Task 6 can only be executed (and its provider-gf CRD fields trusted) after Tasks 1-5 are merged and a new `provider-orgmapper` version/tag is available to bump in `crossplaneProviders.orgmapper` — call this out explicitly when dispatching Task 6/7 so the executor doesn't try to test against an unreleased CRD.

