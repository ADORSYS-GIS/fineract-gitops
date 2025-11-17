# Disaster Recovery Guide

**Last Updated**: 2025-11-10
**Audience**: DevOps Engineers, SREs, Platform Administrators
**Classification**: Critical Operations Document

## Table of Contents

- [Overview](#overview)
- [Disaster Scenarios](#disaster-scenarios)
- [Prerequisites](#prerequisites)
- [Backup Strategies](#backup-strategies)
- [Recovery Procedures](#recovery-procedures)
  - [Scenario 1: Complete Infrastructure Loss](#scenario-1-complete-infrastructure-loss)
  - [Scenario 2: Database Failure](#scenario-2-database-failure)
  - [Scenario 3: Application Deployment Failure](#scenario-3-application-deployment-failure)
  - [Scenario 4: Control Plane Failure](#scenario-4-control-plane-failure)
  - [Scenario 5: Data Corruption](#scenario-5-data-corruption)
- [Testing & Validation](#testing--validation)
- [Post-Recovery Checklist](#post-recovery-checklist)
- [Contact Information](#contact-information)

---

## Overview

This document provides comprehensive disaster recovery (DR) procedures for the Fineract GitOps platform. It covers various disaster scenarios and step-by-step recovery instructions to restore services with minimal data loss and downtime.

### Recovery Objectives

| Metric | Development | UAT | Production |
|--------|-------------|-----|------------|
| **RTO (Recovery Time Objective)** | 4 hours | 2 hours | 1 hour |
| **RPO (Recovery Point Objective)** | 24 hours | 6 hours | 1 hour |
| **Data Loss Tolerance** | Medium | Low | Minimal |

### Disaster Response Team

- **Incident Commander**: Platform Lead
- **Database Administrator**: Responsible for data recovery
- **Infrastructure Engineer**: AWS infrastructure restoration
- **Application Engineer**: Application deployment and validation
- **Communications Lead**: Stakeholder updates

---

## Disaster Scenarios

### Critical (P0)
- Complete infrastructure destruction (region failure)
- Database complete loss or corruption
- Security breach requiring full rebuild

### High (P1)
- Control plane (EKS/ArgoCD) failure
- Multi-service outage
- Significant data loss

### Medium (P2)
- Single service failure
- Partial data loss
- Configuration corruption

### Low (P3)
- Minor configuration issues
- Individual component failures

---

## Prerequisites

### Required Access

Ensure disaster recovery team has:

- **AWS Console Access**:
  - Administrator or PowerUser role
  - Access to production AWS account
  - MFA configured

- **kubectl/EKS Access**:
  ```bash
  aws eks update-kubeconfig --name fineract-prod --region us-east-2
  ```

- **ArgoCD Access**:
  - Admin credentials stored in 1Password/vault
  - CLI authentication configured

- **Git Repository Access**:
  - SSH key or personal access token
  - Write access to repository

- **Sealed Secrets Master Key**:
  - Located in AWS Secrets Manager: `/fineract/sealed-secrets/master-key`
  - Required for decrypting sealed secrets

### Required Tools

```bash
# Install required CLI tools
brew install kubectl awscli terraform argocd kustomize

# Verify installations
kubectl version --client
aws --version
terraform version
argocd version
kustomize version
```

### Documentation Access

- Terraform state file location: `s3://fineract-terraform-state-<account-id>/terraform.tfstate`
- Database backup location: AWS RDS automated backups + manual snapshots
- Secret backup location: AWS Secrets Manager
- GitOps repository: `https://github.com/your-org/fineract-gitops`

---

## Backup Strategies

### Infrastructure (Terraform State)

**Backup Method**: S3 backend with versioning enabled

```bash
# Verify state backup exists
aws s3 ls s3://fineract-terraform-state-<account-id>/ --recursive

# Download state backup
aws s3 cp s3://fineract-terraform-state-<account-id>/terraform.tfstate ./terraform-state-backup.json

# List state versions
aws s3api list-object-versions --bucket fineract-terraform-state-<account-id> --prefix terraform.tfstate
```

**Backup Frequency**: Automatic (on every `terraform apply`)
**Retention**: 30 versions retained in S3

### Database Backups

**Automated Backups** (RDS):
- **Frequency**: Daily
- **Retention**: 7 days (development), 30 days (production)
- **Window**: 03:00-04:00 UTC

**Manual Snapshots**:
```bash
# Create manual snapshot before major changes
aws rds create-db-snapshot \
  --db-instance-identifier fineract-prod \
  --db-snapshot-identifier fineract-prod-$(date +%Y%m%d-%H%M%S)

# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier fineract-prod \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table
```

**Backup Frequency**: Before deployments, weekly
**Retention**: 90 days

### Application Configuration

**Backup Method**: Git repository (version controlled)

```bash
# Clone repository for offline access
git clone https://github.com/your-org/fineract-gitops.git
cd fineract-gitops

# Create backup branch
git branch backup-$(date +%Y%m%d) main
git push origin backup-$(date +%Y%m%d)
```

**Backup Frequency**: Continuous (Git commits)
**Retention**: Indefinite (Git history)

### Secrets Backup

**Sealed Secrets Master Key**:
```bash
# Backup master key to AWS Secrets Manager
kubectl get secret sealed-secrets-key -n kube-system -o yaml > sealed-secrets-master-key.yaml

aws secretsmanager put-secret-value \
  --secret-id /fineract/sealed-secrets/master-key \
  --secret-string "$(cat sealed-secrets-master-key.yaml)"

# Remove local file securely
shred -u sealed-secrets-master-key.yaml
```

**Keycloak Configuration**:
```bash
# Export Keycloak realm configuration
kubectl exec -n fineract-prod deployment/keycloak -- \
  /opt/keycloak/bin/kc.sh export \
  --realm fineract \
  --dir /tmp/keycloak-export

# Copy export to local
kubectl cp fineract-prod/<keycloak-pod>:/tmp/keycloak-export ./keycloak-backup-$(date +%Y%m%d)

# Upload to S3
aws s3 cp keycloak-backup-$(date +%Y%m%d) s3://fineract-backups/keycloak/ --recursive
```

### Persistent Volume Backups

**For critical data on PVs**:
```bash
# Create EBS snapshot
VOLUME_ID=$(kubectl get pv <pv-name> -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | cut -d'/' -f4)
aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Backup of <pv-name> on $(date)" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=fineract-pv-backup-$(date +%Y%m%d)}]"
```

---

## Recovery Procedures

### Scenario 1: Complete Infrastructure Loss

**Situation**: Entire AWS infrastructure destroyed (region failure, account compromise, etc.)

**Impact**: Complete service outage
**RTO**: 2-4 hours
**RPO**: Up to last database backup

#### Step 1: Assess Damage and Activate DR Team

```bash
# Activate incident response
# 1. Notify DR team via PagerDuty/Slack
# 2. Establish war room (Zoom/Slack channel)
# 3. Assign roles per DR plan
```

#### Step 2: Restore AWS Infrastructure

**2.1 Verify AWS Access**:
```bash
aws sts get-caller-identity
aws ec2 describe-vpcs --region us-east-2
```

**2.2 Restore Terraform State** (if needed):
```bash
cd terraform/aws

# If S3 state is lost, restore from backup
aws s3 cp s3://fineract-terraform-state-backup-<account-id>/terraform.tfstate terraform.tfstate

# Or initialize with existing infrastructure
terraform init -backend-config="bucket=fineract-terraform-state-<account-id>"
```

**2.3 Re-provision Infrastructure**:
```bash
# Review and apply infrastructure
terraform plan -var-file=environments/production.tfvars
terraform apply -var-file=environments/production.tfvars

# Capture outputs
terraform output > infrastructure-outputs.txt
```

**Expected Duration**: 30-45 minutes

#### Step 3: Restore Database

**3.1 Identify Latest Snapshot**:
```bash
# Find latest snapshot
aws rds describe-db-snapshots \
  --db-instance-identifier fineract-prod \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime)[-1]' \
  --output json
```

**3.2 Restore Database from Snapshot**:
```bash
SNAPSHOT_ID="fineract-prod-YYYYMMDD-HHMMSS"

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier fineract-prod-restored \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-subnet-group-name <subnet-group-name> \
  --vpc-security-group-ids <security-group-id> \
  --publicly-accessible false

# Monitor restoration progress
aws rds describe-db-instances \
  --db-instance-identifier fineract-prod-restored \
  --query 'DBInstances[0].DBInstanceStatus'
```

**3.3 Update Database Endpoint**:
```bash
# Get new endpoint
NEW_DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier fineract-prod-restored \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "New database endpoint: $NEW_DB_ENDPOINT"

# Update sealed secret (see Step 4.3)
```

**Expected Duration**: 15-30 minutes

#### Step 4: Restore Kubernetes Cluster and Applications

**4.1 Connect to Restored EKS Cluster**:
```bash
aws eks update-kubeconfig --name fineract-prod --region us-east-2
kubectl get nodes
```

**4.2 Install Core Components**:
```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Wait for sealed-secrets controller to be ready
kubectl wait --for=condition=ready pod -n kube-system -l name=sealed-secrets-controller --timeout=300s
```

**4.3 Restore Sealed Secrets Master Key**:
```bash
# Retrieve master key from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id /fineract/sealed-secrets/master-key \
  --query SecretString \
  --output text > sealed-secrets-master-key.yaml

# Replace sealed-secrets key
kubectl replace -f sealed-secrets-master-key.yaml -n kube-system

# Restart sealed-secrets controller to pick up new key
kubectl delete pod -n kube-system -l name=sealed-secrets-controller

# Securely delete local file
shred -u sealed-secrets-master-key.yaml
```

**4.4 Install ArgoCD**:
```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -n argocd -l app.kubernetes.io/name=argocd-server --timeout=600s

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**4.5 Configure ArgoCD**:
```bash
# Login to ArgoCD
ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
argocd login $ARGOCD_SERVER --username admin --password <password-from-previous-step>

# Add Git repository
argocd repo add https://github.com/your-org/fineract-gitops \
  --username <github-username> \
  --password <github-token>

# Apply ArgoCD configuration
kubectl apply -f argocd/config/
kubectl apply -f argocd/projects/
```

**4.6 Deploy Applications via ArgoCD**:
```bash
# Apply application manifests
kubectl apply -f argocd/applications/production/

# Sync all applications
argocd app sync -l env=production

# Monitor sync status
watch argocd app list
```

**Expected Duration**: 30-60 minutes

#### Step 5: Verify Services

**5.1 Check Pod Status**:
```bash
# Verify all pods are running
kubectl get pods -n fineract-prod

# Check for errors
kubectl get events -n fineract-prod --sort-by='.lastTimestamp' | grep -i error
```

**5.2 Test Database Connectivity**:
```bash
# Test from Fineract pod
kubectl exec -n fineract-prod deployment/fineract-write -- \
  wget -qO- http://localhost:8080/fineract-provider/actuator/health | jq .
```

**5.3 Test Application Endpoints**:
```bash
# Test Keycloak
kubectl exec -n fineract-prod deployment/keycloak -- \
  curl -f http://localhost:8080/health

# Test Fineract API
kubectl port-forward -n fineract-prod svc/fineract-write 8080:8080 &
curl -f http://localhost:8080/fineract-provider/actuator/health
```

**5.4 End-to-End Test**:
```bash
# Login via Keycloak
# Access web application
# Perform sample transaction
# Verify data integrity
```

**Expected Duration**: 15-30 minutes

#### Step 6: Update DNS and Enable Traffic

**6.1 Update DNS Records**:
```bash
# Get new Load Balancer endpoints
kubectl get ingress -n fineract-prod

# Update DNS A records to point to new ALB
# (via Route53, CloudFlare, etc.)
```

**6.2 Verify DNS Propagation**:
```bash
dig fineract.your-domain.com
nslookup fineract.your-domain.com 8.8.8.8
```

**6.3 Enable Monitoring**:
```bash
# Sync monitoring application
argocd app sync monitoring-prod

# Verify Prometheus is scraping
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets
```

**Expected Duration**: 15-30 minutes

---

### Scenario 2: Database Failure

**Situation**: Database corruption, accidental deletion, or RDS instance failure

**Impact**: Application cannot read/write data
**RTO**: 30 minutes - 1 hour
**RPO**: Up to last backup (typically < 5 minutes)

#### Step 1: Assess Database Status

```bash
# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier fineract-prod \
  --query 'DBInstances[0].DBInstanceStatus'

# Check for recent events
aws rds describe-events \
  --source-identifier fineract-prod \
  --duration 60
```

#### Step 2: Determine Recovery Strategy

**If instance is down**:
→ Proceed with restore from snapshot (Step 3)

**If data is corrupted but instance is running**:
→ Create snapshot, then restore to new instance (Step 3)

**If accidental deletion**:
→ Restore from latest automated backup (Step 4)

#### Step 3: Restore from Snapshot

```bash
# Create snapshot of current state (if possible)
aws rds create-db-snapshot \
  --db-instance-identifier fineract-prod \
  --db-snapshot-identifier fineract-prod-pre-recovery-$(date +%Y%m%d-%H%M%S)

# Identify recovery snapshot
aws rds describe-db-snapshots \
  --db-instance-identifier fineract-prod \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime)[-1]'

# Restore to new instance
SNAPSHOT_ID="<snapshot-id>"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier fineract-prod-recovery \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-subnet-group-name fineract-db-subnet \
  --vpc-security-group-ids <sg-id>

# Wait for restoration
aws rds wait db-instance-available --db-instance-identifier fineract-prod-recovery
```

#### Step 4: Update Application Configuration

```bash
# Get new database endpoint
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier fineract-prod-recovery \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Update database configuration
# Edit apps/fineract/overlays/production/database-config-patch.yaml
# or update sealed secret with new endpoint

# Apply changes
kubectl apply -k environments/production/

# Or sync via ArgoCD
argocd app sync fineract-prod-fineract

# Restart Fineract pods to pick up new database
kubectl rollout restart deployment -n fineract-prod -l app=fineract
```

#### Step 5: Validate Recovery

```bash
# Check application logs
kubectl logs -n fineract-prod -l app=fineract --tail=100 | grep -i database

# Test database connectivity
kubectl exec -n fineract-prod deployment/fineract-write -- \
  nc -zv $NEW_ENDPOINT 5432

# Verify data integrity
# Run sample queries to check critical data
```

#### Step 6: Cutover and Cleanup

```bash
# Once validated, delete old instance and rename new one
aws rds modify-db-instance \
  --db-instance-identifier fineract-prod \
  --new-db-instance-identifier fineract-prod-old \
  --apply-immediately

aws rds modify-db-instance \
  --db-instance-identifier fineract-prod-recovery \
  --new-db-instance-identifier fineract-prod \
  --apply-immediately

# Update application to use original endpoint name

# After validation period, delete old instance
aws rds delete-db-instance \
  --db-instance-identifier fineract-prod-old \
  --skip-final-snapshot
```

---

### Scenario 3: Application Deployment Failure

**Situation**: Bad deployment causing application outage

**Impact**: Application unavailable or degraded
**RTO**: 15-30 minutes
**RPO**: N/A (configuration rollback)

#### Step 1: Identify Failed Deployment

```bash
# Check deployment status
kubectl get deployments -n fineract-prod
kubectl rollout status deployment/<deployment-name> -n fineract-prod

# Check pod errors
kubectl get pods -n fineract-prod | grep -v Running
kubectl describe pod <failing-pod> -n fineract-prod
kubectl logs <failing-pod> -n fineract-prod --previous
```

#### Step 2: Rollback via ArgoCD

```bash
# View application history
argocd app history fineract-prod-fineract

# Rollback to previous version
argocd app rollback fineract-prod-fineract <revision-number>

# Or rollback to last successful sync
argocd app rollback fineract-prod-fineract
```

#### Step 3: Rollback via kubectl (if ArgoCD unavailable)

```bash
# View deployment history
kubectl rollout history deployment/<deployment-name> -n fineract-prod

# Rollback to previous revision
kubectl rollout undo deployment/<deployment-name> -n fineract-prod

# Rollback to specific revision
kubectl rollout undo deployment/<deployment-name> -n fineract-prod --to-revision=<revision>

# Monitor rollback
kubectl rollout status deployment/<deployment-name> -n fineract-prod
```

#### Step 4: Verify Recovery

```bash
# Check pod status
kubectl get pods -n fineract-prod

# Test application endpoints
kubectl exec -n fineract-prod deployment/fineract-write -- \
  curl -f http://localhost:8080/fineract-provider/actuator/health
```

#### Step 5: Investigate Root Cause

```bash
# Review failed deployment logs
kubectl logs deployment/<deployment-name> -n fineract-prod --previous

# Check configuration differences
argocd app diff fineract-prod-fineract

# Review recent commits
cd fineract-gitops
git log --oneline -10
git diff HEAD~1 HEAD -- environments/production/
```

---

### Scenario 4: Control Plane Failure (ArgoCD/EKS)

**Situation**: ArgoCD or EKS control plane unavailable

**Impact**: Cannot deploy changes, cluster management impaired
**RTO**: 1-2 hours
**RPO**: N/A

#### EKS Control Plane Failure

**AWS automatically handles this** - EKS control plane is multi-AZ and highly available.

**If prolonged outage**:
```bash
# Contact AWS Support immediately
aws support create-case \
  --subject "EKS Control Plane Unavailable - Urgent" \
  --service-code "eks" \
  --severity-code "urgent" \
  --category-code "general-guidance" \
  --communication-body "Production EKS cluster control plane unavailable: fineract-prod"

# Monitor AWS Health Dashboard
aws health describe-events --filter eventTypeCategories=issue
```

#### ArgoCD Failure

**If ArgoCD pods are down**:
```bash
# Check ArgoCD pod status
kubectl get pods -n argocd

# Restart ArgoCD components
kubectl rollout restart deployment -n argocd
kubectl rollout restart statefulset -n argocd

# If persistent storage issue, restore from Git
kubectl delete namespace argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Re-apply configuration
kubectl apply -f argocd/config/
kubectl apply -f argocd/applications/production/
```

**Temporary workaround - Deploy directly**:
```bash
# If ArgoCD is completely down, deploy manually
kubectl apply -k environments/production/

# Monitor deployment
kubectl rollout status deployment -n fineract-prod --watch
```

---

### Scenario 5: Data Corruption

**Situation**: Application data corrupted (logical corruption, not hardware failure)

**Impact**: Data integrity compromised
**RTO**: 2-4 hours
**RPO**: Up to last clean backup

#### Step 1: Stop Writes to Database

```bash
# Scale down write services immediately
kubectl scale deployment fineract-write --replicas=0 -n fineract-prod
kubectl scale deployment fineract-batch --replicas=0 -n fineract-prod

# Enable read-only mode for read service (if possible)
# This is application-specific
```

#### Step 2: Assess Corruption Extent

```bash
# Connect to database
kubectl run -n fineract-prod db-client --rm -it --image=postgres:15 -- \
  psql -h <rds-endpoint> -U fineract -d fineract

# Run data integrity checks
-- Check for orphaned records
-- Check referential integrity
-- Identify corrupted data range
```

#### Step 3: Identify Last Good Backup

```bash
# Review backup timeline
aws rds describe-db-snapshots \
  --db-instance-identifier fineract-prod \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table

# Correlate with application logs to find last known good state
```

#### Step 4: Restore to Recovery Database

```bash
# Restore to separate instance for data extraction
SNAPSHOT_ID="<last-good-snapshot-id>"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier fineract-prod-data-recovery \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-subnet-group-name fineract-db-subnet \
  --vpc-security-group-ids <sg-id>

# Wait for restoration
aws rds wait db-instance-available --db-instance-identifier fineract-prod-data-recovery
```

#### Step 5: Extract and Merge Clean Data

```bash
# This is highly application-specific
# Example: Export clean data from recovery database

kubectl run -n fineract-prod db-export --rm -it --image=postgres:15 -- bash

# From within pod:
pg_dump -h <recovery-endpoint> -U fineract -d fineract \
  -t <clean-tables> -t <more-tables> \
  --data-only --inserts > /tmp/clean-data.sql

# Review and sanitize SQL if needed

# Import clean data (with conflict resolution)
psql -h <prod-endpoint> -U fineract -d fineract < /tmp/clean-data.sql
```

#### Step 6: Validate and Resume Operations

```bash
# Run data integrity checks on production database

# Scale up write services
kubectl scale deployment fineract-write --replicas=2 -n fineract-prod
kubectl scale deployment fineract-batch --replicas=1 -n fineract-prod

# Monitor for issues
kubectl logs -n fineract-prod -l app=fineract --tail=100 -f
```

---

## Testing & Validation

### Regular DR Drills

**Frequency**: Quarterly
**Scope**: Full infrastructure recovery (non-production)

#### DR Drill Procedure

```bash
# 1. Schedule drill (communicate to stakeholders)
# 2. Destroy non-production environment
# 3. Follow recovery procedures
# 4. Document timing and issues
# 5. Update DR plan based on learnings
```

### Backup Validation

**Frequency**: Monthly

```bash
#!/bin/bash
# Validate database backups

# Get latest snapshot
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier fineract-prod \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime)[-1].DBSnapshotIdentifier' \
  --output text)

echo "Testing snapshot: $LATEST_SNAPSHOT"

# Restore to temporary instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier fineract-backup-test-$(date +%Y%m%d) \
  --db-snapshot-identifier $LATEST_SNAPSHOT \
  --db-subnet-group-name fineract-db-subnet \
  --vpc-security-group-ids <sg-id>

# Wait for restoration
aws rds wait db-instance-available --db-instance-identifier fineract-backup-test-$(date +%Y%m%d)

# Validate data integrity
# Run test queries

# Delete test instance
aws rds delete-db-instance \
  --db-instance-identifier fineract-backup-test-$(date +%Y%m%d) \
  --skip-final-snapshot

echo "Backup validation complete"
```

---

## Post-Recovery Checklist

After completing recovery procedures:

- [ ] All services are running and healthy
- [ ] Database connectivity verified
- [ ] Authentication (Keycloak) is functional
- [ ] API endpoints responding correctly
- [ ] Monitoring and alerting operational
- [ ] DNS propagated to new infrastructure
- [ ] SSL/TLS certificates valid
- [ ] Data integrity checks passed
- [ ] End-to-end transaction test successful
- [ ] Backups re-enabled and scheduled
- [ ] Team notified of recovery completion
- [ ] Incident report created
- [ ] Root cause analysis scheduled
- [ ] DR plan updated with lessons learned

### Communication Template

```
Subject: [RESOLVED] Production Recovery Complete

Team,

The production environment has been successfully recovered following [incident description].

Recovery Summary:
- Incident Start: [timestamp]
- Recovery Complete: [timestamp]
- Total Downtime: [duration]
- Data Loss: [none/minimal/description]
- Root Cause: [brief description]

All services are operational and monitoring has been restored. Post-incident review scheduled for [date/time].

Thank you for your patience and support during this incident.

[Your Name]
Incident Commander
```

---

## Contact Information

### Emergency Contacts

- **On-Call Engineer**: +1-XXX-XXX-XXXX (PagerDuty)
- **Platform Lead**: platform-lead@example.com
- **Database Administrator**: dba-team@example.com
- **Security Team**: security@example.com

### Escalation Path

1. **Level 1**: On-call engineer
2. **Level 2**: Platform lead + DBA
3. **Level 3**: VP Engineering + CTO
4. **Level 4**: CEO (for major incidents)

### External Support

- **AWS Support**: Premium Support (24/7)
- **Vendor Support**: [List critical vendors]

---

## Appendices

### Appendix A: Recovery Time Estimates

| Task | Estimated Duration |
|------|-------------------|
| Infrastructure provisioning (Terraform) | 30-45 minutes |
| Database restoration from snapshot | 15-30 minutes |
| Kubernetes cluster bootstrap | 15-20 minutes |
| ArgoCD installation and configuration | 15-20 minutes |
| Application deployment | 20-30 minutes |
| DNS propagation | 5-60 minutes |
| Validation and testing | 15-30 minutes |
| **Total (Complete Recovery)** | **2-4 hours** |

### Appendix B: Critical Secrets Locations

| Secret | Location | Access Method |
|--------|----------|---------------|
| Sealed Secrets Master Key | AWS Secrets Manager | `/fineract/sealed-secrets/master-key` |
| Database Root Password | AWS Secrets Manager | `/fineract/database/root-password` |
| ArgoCD Admin Password | Kubernetes Secret | `argocd-initial-admin-secret` in `argocd` namespace |
| Keycloak Admin Password | Sealed Secret | `keycloak-admin-credentials` in app namespace |
| Terraform State Encryption Key | AWS KMS | Key alias: `terraform-state-key` |

### Appendix C: Useful Commands Cheat Sheet

```bash
# Quick cluster status
kubectl get nodes && kubectl get pods --all-namespaces | grep -v Running

# Force ArgoCD sync
argocd app sync --force --replace <app-name>

# Emergency rollback
kubectl rollout undo deployment/<name> -n <namespace>

# Database snapshot
aws rds create-db-snapshot --db-instance-identifier <id> --db-snapshot-identifier <name>

# Scale down all non-critical services
kubectl scale deployment --replicas=0 -n fineract-prod -l tier=non-critical

# Export all Kubernetes resources
kubectl get all -n fineract-prod -o yaml > fineract-prod-backup.yaml
```

---

**Document Version**: 1.0
**Last Tested**: [Date of last DR drill]
**Next Review Date**: [Quarterly]
**Document Owner**: Platform Team
