# Disaster Recovery Guide

**Complete backup and disaster recovery procedures for Fineract GitOps**

This directory contains comprehensive disaster recovery (DR) documentation, procedures, and automation for the Fineract platform deployed on Kubernetes.

## Quick Links

| Document | Purpose |
|----------|---------|
| **[DR Guide](DR_GUIDE.md)** | Comprehensive backup and restore procedures, RTO/RPO definitions, testing, and responsibilities |



## Quick Start

### Prerequisites

1. ✅ MinIO deployed and accessible
2. ✅ Velero installed with MinIO backend configured
3. ✅ PostgreSQL backup CronJob running
4. ✅ Sealed secrets created for backup credentials
5. ✅ velero CLI installed locally

### Verify Backups Are Running

```bash
# Check PostgreSQL backup CronJob
kubectl get cronjob postgresql-backup -n fineract
kubectl get jobs -n fineract -l component=backup

# Check Velero schedules
kubectl get schedules -n velero

# Check Velero backups
velero backup get

# Check MinIO storage
kubectl port-forward -n backup svc/minio 9001:9001
# Open http://localhost:9001 (MinIO Console)
# Login with credentials from minio-credentials secret
# Browse fineract-backups bucket
```

### Perform Manual Backup

```bash
# Before major deployment or change
cd scripts/backup
./backup-postgresql.sh

# Or use Velero for full cluster backup
velero backup create manual-backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces fineract-production \
  --wait
```

### Test Restore (Dry Run)

```bash
# Test PostgreSQL restore (doesn't actually restore)
cd scripts/backup
./restore-postgresql.sh --dry-run latest

# Test Velero restore (creates resources with different namespace)
velero restore create test-restore \
  --from-backup weekly-cluster-backup-20250126 \
  --namespace-mappings fineract-production:fineract-test
```

## Backup Validation

All backups should be validated regularly:

- **Daily:** Automated checks via backup CronJob (checksums, file size)
- **Weekly:** Manual spot-check of backup files in MinIO
- **Monthly:** Full restore test in non-production environment
- **Quarterly:** DR drill with complete cluster restore

## Emergency Contacts

| Role | Contact | Phone | Slack |
|------|---------|-------|-------|
| **Platform Lead** | (Name) | +1-XXX-XXX-XXXX | @platform-lead |
| **DBA** | (Name) | +1-XXX-XXX-XXXX | @dba |
| **SRE On-Call** | PagerDuty | - | #sre-oncall |
| **Backup Vendor** | MinIO Support | - | support@min.io |

## Documentation

| Document | Description |
|----------|-------------|
| **[DR Guide](DR_GUIDE.md)** | Comprehensive backup and restore procedures, RTO/RPO definitions, testing, and responsibilities |

## Related Documentation

- [Secrets Management](../../docs/SECRETS_MANAGEMENT.md) - Creating backup credentials
- [MinIO README](../../apps/minio/README.md) - MinIO deployment and configuration
- [Velero README](../../apps/velero/README.md) - Velero deployment and usage
- [PostgreSQL README](../../apps/postgresql/base/README.md) - Database administration

---

**Created:** 2025-10-26  
**Status:** ✅ Production Ready  
**Last Reviewed:** 2025-10-26  
**Next Review:** 2026-01-26 (Quarterly)
