# Barman Cloud Plugin Migration Plan

**Date:** 2026-05-13  
**Status:** Planning  
**Priority:** Medium (required before CNPG 1.30)

## Summary

CloudNativePG is deprecating native barman backup support starting from v1.26 and will **completely remove it in v1.30**. We need to migrate to the new plugin-based architecture.

**Current state:**
- CNPG operator version: 1.29.1
- Chart version: 0.28.0
- Native barman backups: Working but deprecated
- Barman cloud plugin: Not installed

**Target state:**
- Install barman-cloud plugin alongside CNPG operator
- Migrate Crossplane composition to use `ObjectStore` CRD
- Update all clusters using barman backup

## Timeline

| Milestone | Target | Notes |
|-----------|--------|-------|
| CNPG 1.26 | Released | Deprecation started |
| CNPG 1.29 | Current | Warnings shown, still works |
| CNPG 1.30 | Future | Native support removed |

**Recommendation:** Complete migration before upgrading to CNPG 1.30.

## Scope

### What changes

1. **cloudnative-pg-operator helm chart** - Add barman-cloud plugin deployment
2. **Crossplane postgres-cnpg composition** - Switch from inline `barmanObjectStore` to `ObjectStore` CRD
3. **All clusters using barman backup** - Migration during composition update

### Affected clusters

Any cluster with `barmanBackup.enabled: true` in their Postgres CR:
- obs-us-east-ct: iam-dex (just enabled)
- Other clusters TBD (need audit)

## Architecture Changes

### Current (Deprecated)

```yaml
# In CNPG Cluster spec
spec:
  backup:
    barmanObjectStore:
      destinationPath: s3://bucket/path
      s3Credentials:
        inheritFromIAMRole: true
      wal:
        compression: gzip
    retentionPolicy: "7d"
```

### New (Plugin-based)

```yaml
# Separate ObjectStore CRD
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: cluster-backup
spec:
  configuration:
    destinationPath: s3://bucket/path
    s3Credentials:
      inheritFromIAMRole: true
    wal:
      compression: gzip
    data:
      compression: gzip
  retentionPolicy: "7d"

---
# In CNPG Cluster spec
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: cluster-backup

---
# ScheduledBackup
spec:
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
    parameters:
      barmanObjectName: cluster-backup
```

## Implementation Plan

### Phase 1: Helm Chart Update

**Modify:** `charts/cloudnative-pg-operator`

1. Add barman-cloud plugin deployment template
2. Add values for plugin configuration
3. Plugin must be in same namespace as operator (cnpg-system)
4. Requires cert-manager (already installed)

**New files:**
- `templates/barman-cloud-plugin.yaml` - Plugin deployment via ArgoCD Application

**Values additions:**
```yaml
barmanCloudPlugin:
  enabled: true
  # renovate: datasource=github-releases depName=cloudnative-pg/plugin-barman-cloud
  version: v0.12.0
  image: "${sharedServicesAccountId}.dkr.ecr.${region}.amazonaws.com/github/cloudnative-pg/plugin-barman-cloud:0.12.0"
```

### Phase 2: Crossplane Composition Update

**Modify:** `postgres-cnpg` composition in dip-compositions repo

1. When `barmanBackup.enabled: true`:
   - Create `ObjectStore` CRD instead of inline config
   - Add plugin reference to Cluster spec
   - Update `ScheduledBackup` to use `method: plugin`

2. Keep IAM resources (Role, Policy, Attachment) - still needed for IRSA

3. Handle migration path:
   - New clusters: Use plugin approach
   - Existing clusters: Composition update triggers migration

### Phase 3: Rollout

1. Deploy updated helm chart to all clusters
2. Update Crossplane composition
3. Existing clusters will reconcile with new configuration
4. Verify backups continue working

## Migration Considerations

### Breaking changes

- `retentionPolicy` moves from Cluster to ObjectStore
- `ScheduledBackup` method changes from `barmanObjectStore` to `plugin`
- Different metrics names (monitoring dashboards may need updates)

### Safety

- Plugin can coexist with deprecated native support during transition
- Backups already in S3 remain accessible
- Point-in-time recovery continues to work

### Rollback

If issues occur:
1. Revert composition to use native barmanObjectStore
2. CNPG will use deprecated path until 1.30
3. Buys time to fix plugin issues

## Testing Plan

1. Deploy to dev/test cluster first
2. Verify:
   - Plugin pod running in cnpg-system
   - ObjectStore CRD created and healthy
   - Manual backup succeeds
   - Scheduled backup works
   - WAL archiving continues
   - Point-in-time recovery works
3. Monitor for 24-48 hours before production

## Open Questions

1. Should we mirror the plugin image to ECR like we do for CNPG?
2. Do we need to update monitoring/alerting for new metrics?
3. Which clusters currently use barman backup? (audit needed)
4. Should we upgrade CNPG operator version at the same time?

## References

- [Migration Guide](https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/)
- [Plugin Installation](https://cloudnative-pg.io/plugin-barman-cloud/docs/installation/)
- [Plugin Releases](https://github.com/cloudnative-pg/plugin-barman-cloud/releases)
- [CloudNativePG 1.26 Release Notes](https://cloudnative-pg.io/documentation/1.26/release_notes/)
