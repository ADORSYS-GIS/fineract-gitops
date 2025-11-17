# Disaster Recovery: Backup and Restore Procedures

This document outlines the comprehensive backup and restore procedures for the Fineract GitOps platform. It covers all critical components, including the AWS RDS PostgreSQL database, Keycloak configuration, Fineract application data, and Kubernetes manifests.

## Table of Contents

1.  [Introduction](#introduction)
2.  [Recovery Time Objective (RTO) and Recovery Point Objective (RPO)](#recovery-time-objective-rto-and-recovery-point-objective-rpo)
3.  [Backup Procedures](#backup-procedures)
    *   [AWS RDS PostgreSQL Database](#aws-rds-postgresql-database)
    *   [Keycloak Configuration](#keycloak-configuration)
    *   [Fineract Application Data](#fineract-application-data)
    *   [Kubernetes Manifests](#kubernetes-manifests)
4.  [Restore Procedures](#restore-procedures)
    *   [AWS RDS PostgreSQL Database Restore](#aws-rds-postgresql-database-restore)
    *   [Keycloak Configuration Restore](#keycloak-configuration-restore)
    *   [Fineract Application Data Restore](#fineract-application-data-restore)
    *   [Kubernetes Manifests Restore](#kubernetes-manifests-restore)
5.  [Testing and Validation](#testing-and-validation)
6.  [Responsibilities](#responsibilities)
7.  [References](#references)

## 1. Introduction

Disaster recovery (DR) is a critical aspect of maintaining the availability and integrity of the Fineract platform. This guide provides the necessary steps to back up and restore all essential components, ensuring business continuity in the event of a disaster.

## 2. Recovery Time Objective (RTO) and Recovery Point Objective (RPO)

### Recovery Time Objective (RTO)

Maximum acceptable time to restore service after an outage.

| Environment | RTO | Justification |
|-------------|-----|---------------|
| **Production** | 4 hours | Critical banking operations, regulatory requirements |
| **UAT** | 8 hours | Testing environment, can tolerate longer outage |
| **Dev** | 24 hours | Development environment, best effort |

### Recovery Point Objective (RPO)

Maximum acceptable data loss measured in time.

| Environment | RPO | Backup Strategy |
|-------------|-----|-----------------|
| **Production** | 24 hours | Daily backups at 2 AM |
| **UAT** | 24 hours | Daily backups at 2 AM |
| **Dev** | 48 hours | Daily backups, relaxed retention |

### Backup Retention Policy

| Backup Type | Frequency | Retention | Storage Location |
|-------------|-----------|-----------|------------------|
| **Daily** | Daily 2 AM | 7 days | MinIO |
| **Weekly** | Sunday 1 AM | 4 weeks | MinIO |
| **Monthly** | 1st Sunday | 12 months | MinIO |

Total storage required: ~550Gi (PostgreSQL dumps + Velero cluster backups)


## 3. Backup Procedures

### AWS RDS PostgreSQL Database

AWS RDS provides automated backups and manual snapshots.

*   **Automated Backups**:
    *   **Frequency**: Daily (configurable backup window).
    *   **Retention**: 7 days for Production, 1-3 days for Dev/UAT (configured via Terraform).
    *   **Mechanism**: RDS automatically takes daily snapshots and stores transaction logs, enabling Point-in-Time Recovery (PITR).
    *   **Verification**: Regularly monitor RDS backup status in the AWS Console or via CloudWatch metrics.

*   **Manual Snapshots (for Major Releases/Upgrades)**:
    *   **Purpose**: To create a known good restore point before significant changes (e.g., Fineract version upgrades).
    *   **Procedure**:
        1.  Navigate to AWS RDS Console -> Databases.
        2.  Select the Fineract PostgreSQL instance.
        3.  Actions -> Take snapshot.
        4.  Provide a descriptive snapshot name (e.g., `fineract-prod-pre-v1.13.0-upgrade`).
    *   **Retention**: Manual snapshots are retained indefinitely until manually deleted.

### Keycloak Configuration

Keycloak configuration is managed as code within this GitOps repository.

*   **Mechanism**: The `operations/keycloak-config/config/realm-fineract.yaml` and related files define the Keycloak realm, clients, and roles. These are version-controlled in Git.
*   **Backup**: The Git repository itself serves as the backup for Keycloak configuration.
*   **Procedure**: Ensure all changes to Keycloak configuration are committed and pushed to the remote Git repository.
    ```bash
    git add operations/keycloak-config/
    git commit -m "feat: Update Keycloak realm configuration"
    git push origin main
    ```

### Fineract Application Data

Fineract application data (e.g., system codes, roles, notification templates) is managed as YAML files within `operations/fineract-data/data/`.

*   **Mechanism**: These YAML files are version-controlled in Git.
*   **Backup**: The Git repository serves as the backup for this application data.
*   **Procedure**: Ensure all changes to Fineract application data are committed and pushed to the remote Git repository.
    ```bash
    git add operations/fineract-data/data/
    git commit -m "feat: Update Fineract system codes"
    git push origin main
    ```

### Kubernetes Manifests

All Kubernetes manifests (deployments, services, ingresses, etc.) are managed as code within this GitOps repository.

*   **Mechanism**: All `.yaml` files in `apps/`, `environments/`, `infrastructure/`, and `operations/` directories are version-controlled.
*   **Backup**: The Git repository serves as the backup for all Kubernetes manifests.
*   **Procedure**: Ensure all changes to Kubernetes manifests are committed and pushed to the remote Git repository.
    ```bash
    git add apps/ environments/ infrastructure/ operations/
    git commit -m "feat: Update Kubernetes deployment for Fineract"
    git push origin main
    ```

## 4. Restore Procedures

### AWS RDS PostgreSQL Database Restore

Restoring the RDS database is the most critical step for data recovery.

*   **Point-in-Time Recovery (PITR)**:
    *   **Purpose**: To restore the database to a specific point in time within the backup retention period.
    *   **Procedure**:
        1.  Navigate to AWS RDS Console -> Databases.
        2.  Select the Fineract PostgreSQL instance.
        3.  Actions -> Restore to point in time.
        4.  Choose the desired date and time.
        5.  Specify a new DB instance identifier (e.g., `fineract-prod-restored`).
        6.  Configure other settings (VPC, security groups) to match the original instance or a recovery environment.
        7.  Click "Restore DB instance".
        8.  Once the new instance is available, update Fineract application configurations (e.g., `RDS_ENDPOINT` in secrets) to point to the restored instance.
    *   **Note**: This creates a *new* RDS instance. The original instance remains untouched.

*   **Restore from Manual Snapshot**:
    *   **Purpose**: To restore the database from a specific manual snapshot.
    *   **Procedure**:
        1.  Navigate to AWS RDS Console -> Snapshots.
        2.  Select the desired manual snapshot.
        3.  Actions -> Restore snapshot.
        4.  Specify a new DB instance identifier.
        5.  Configure other settings as needed.
        6.  Click "Restore DB instance".
        7.  Update Fineract application configurations to point to the restored instance.

### Keycloak Configuration Restore

Restoring Keycloak configuration involves reapplying the version-controlled manifests.

*   **Procedure**:
    1.  Ensure the Keycloak service is running in the target environment.
    2.  If the Keycloak realm is corrupted or missing, delete the existing Keycloak application in ArgoCD (if applicable) or manually delete the realm in Keycloak.
    3.  Apply the Keycloak configuration manifests from the Git repository. If using ArgoCD, sync the `keycloak-config` application.
        ```bash
        kubectl apply -f argocd/applications/operations/keycloak-config.yaml
        # Or if already deployed via ArgoCD:
        argocd app sync keycloak-config
        ```
    4.  Monitor the `apply-keycloak-config` job and `export-keycloak-secrets` job to ensure successful configuration and secret extraction.

### Fineract Application Data Restore

Restoring Fineract application data involves reapplying the version-controlled YAML files.

*   **Procedure**:
    1.  Ensure the Fineract service is running and connected to the restored database.
    2.  If data is missing or corrupted, apply the Fineract data loading applications from the Git repository. If using ArgoCD, sync the `fineract-data-{env}` application.
        ```bash
        kubectl apply -f argocd/applications/operations/fineract-data-dev.yaml # for dev
        # Or if already deployed via ArgoCD:
        argocd app sync fineract-data-dev
        ```
    3.  Monitor the data loading jobs to ensure successful data re-population.

### Kubernetes Manifests Restore

Restoring Kubernetes manifests involves syncing the GitOps repository with the cluster.

*   **Procedure**:
    1.  Ensure your local Git repository is clean and up-to-date with the desired state (e.g., `git checkout main && git pull origin main`).
    2.  If using ArgoCD, simply trigger a sync for the relevant applications. ArgoCD will reconcile the cluster state with the manifests in Git.
        ```bash
        argocd app sync <application-name>
        # Or sync all applications
        argocd app sync --all
        ```
    3.  If not using ArgoCD, manually apply the manifests:
        ```bash
        kubectl apply -k apps/fineract/overlays/dev/ # Example for dev environment
        ```

## 5. Testing and Validation

Regular testing of backup and restore procedures is crucial to ensure their effectiveness.

*   **Automated Backup Verification**:
    *   Monitor AWS CloudWatch metrics for RDS backup success/failure.
    *   Implement automated checks to verify the integrity of manual snapshots (e.g., by restoring to a temporary instance).
*   **DR Drills**:
    *   **Frequency**: Conduct DR drills at least annually (or quarterly for critical systems).
    *   **Scope**: Simulate a disaster scenario (e.g., region outage, database corruption) in a non-production environment.
    *   **Procedure**: Execute the full restore procedures outlined in this document.
    *   **Validation**: Verify RTO/RPO targets are met and all systems are fully functional post-recovery. Document any lessons learned and update procedures.

## 6. Responsibilities

| Role/Team       | Responsibility                                                              |
| :-------------- | :-------------------------------------------------------------------------- |
| DevOps Team     | Define and maintain DR procedures, automate backups, conduct DR drills.     |
| Application Team | Validate application functionality post-restore, assist in data verification. |
| Infrastructure Team | Manage AWS RDS, Kubernetes cluster, network connectivity.                   |

## 7. References

*   [AWS RDS Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)
*   [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
*   [Keycloak Documentation](https://www.keycloak.org/documentation)
*   [Fineract API Documentation](https://fineract.apache.org/docs/api/)
*   [RTO_RPO_DEFINITIONS.md](RTO_RPO_DEFINITIONS.md)
