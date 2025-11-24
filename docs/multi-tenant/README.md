# Fineract GitOps Multi-Tenant Documentation

**Version:** 1.0
**Last Updated:** 2025-11-24
**Status:** Complete

## Overview

This directory contains complete documentation for transforming the Fineract GitOps platform from single-tenant to multi-tenant SaaS architecture.

### Architecture Summary

- **Tenant Identification**: Subdomain-based (tenant1.app.example.com)
- **Identity Management**: Keycloak Organizations (single realm)
- **Database Isolation**: Separate PostgreSQL database per tenant on shared RDS
- **Authentication**: OAuth2/OIDC with JWT token containing tenant claim
- **Routing**: NGINX Ingress with wildcard DNS
- **Provisioning**: Manual workflow with helper scripts

### Key Benefits

- **Cost Efficiency**: Shared infrastructure reduces per-tenant costs by ~70%
- **Data Isolation**: Each tenant has separate database ensuring compliance
- **Scalability**: Architecture supports 100+ tenants on single RDS instance
- **Security**: Multiple layers of tenant validation (DNS, JWT, database)
- **Operational Simplicity**: Clear procedures and automation scripts

---

## Documents

### 1. MULTI_TENANT_ARCHITECTURE.md

**Purpose:** Complete architecture design document
**Audience:** Solution Architects, Technical Leads, DevOps Engineers

**Contents:**
- Executive summary and architecture decisions
- High-level architecture diagrams (Mermaid)
- Authentication flow with Keycloak Organizations
- Database architecture (shared RDS, separate databases)
- Request flow with tenant isolation
- Component details:
  - Ingress configuration (wildcard routing)
  - OAuth2 Proxy setup
  - Keycloak Organizations configuration
  - Fineract multi-tenant config
  - Redis tenant isolation
  - S3 tenant isolation
- Capacity planning and scaling
- Security considerations
- Monitoring and observability
- Cost analysis
- Disaster recovery
- Performance characteristics

**When to Read:**
- Before starting implementation
- When making architectural decisions
- For understanding overall system design

---

### 2. IMPLEMENTATION_GUIDE.md

**Purpose:** Step-by-step implementation instructions
**Audience:** DevOps Engineers, Platform Engineers, Implementation Teams

**Contents:**
- Implementation phases (0-6)
- Phase 0: Pre-implementation setup
- Phase 1: Keycloak multi-tenant setup
  - Enable Organizations feature
  - Create multi-tenant realm configuration
  - Create test organizations
  - Create test users
  - Validate JWT tokens
- Phase 2: Database multi-tenant configuration
  - Terraform updates
  - Database creation scripts
  - Schema migration per tenant
  - Database init job updates
- Phase 3: Application layer changes
  - Fineract deployment updates
  - Multi-tenant environment variables
  - Connection pool configuration
- Phase 4: Ingress and routing
  - Wildcard DNS setup
  - Wildcard TLS certificates
  - Multi-tenant ingress configuration
  - OAuth2 Proxy updates
- Phase 5: Testing and validation
  - End-to-end testing
  - Tenant isolation verification
  - Performance testing
  - Monitoring validation
- Phase 6: Migration of default tenant
  - Data migration procedures
  - User migration to organizations
  - Deprecation of single-tenant setup
- Post-implementation:
  - Documentation updates
  - Team training
  - Security audit

**When to Use:**
- During implementation of multi-tenant architecture
- As a checklist for each phase
- For troubleshooting implementation issues

**Estimated Time:** 14-22 days

---

### 3. TENANT_PROVISIONING_GUIDE.md

**Purpose:** Operational guide for provisioning and managing tenants
**Audience:** Platform Administrators, Operations Team, Support Engineers

**Contents:**
- Provisioning workflow and diagrams
- Prerequisites and required information
- Step-by-step provisioning procedure:
  1. Validate tenant information
  2. Create Keycloak organization
  3. Create tenant database
  4. Run schema migration
  5. Load initial configuration
  6. Create tenant admin user
  7. Test tenant access
  8. Document tenant details
  9. Notify tenant admin
- Tenant management operations:
  - Adding users
  - Updating configuration
  - Monitoring usage
  - Scaling resources
- Tenant deprovisioning workflow
- Troubleshooting common issues
- Complete checklist for new tenant provisioning

**When to Use:**
- When provisioning a new tenant
- For day-to-day tenant management
- When deprovisioning a tenant
- For troubleshooting tenant-specific issues

**Time to Provision:** 30-60 minutes (manual) or 5-10 minutes (automated)

---

## Quick Start

### For Architects and Technical Leads

1. Read [MULTI_TENANT_ARCHITECTURE.md](MULTI_TENANT_ARCHITECTURE.md) completely
2. Review architecture diagrams and component details
3. Understand tenant isolation mechanisms
4. Review capacity planning and cost analysis
5. Plan implementation timeline

### For Implementation Teams

1. Read [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)
2. Set up development environment (Phase 0)
3. Follow each phase sequentially
4. Test thoroughly after each phase
5. Document any deviations or customizations

### For Operations Teams

1. Read [TENANT_PROVISIONING_GUIDE.md](TENANT_PROVISIONING_GUIDE.md)
2. Familiarize yourself with provisioning scripts
3. Practice provisioning test tenant
4. Set up monitoring and alerting
5. Establish on-call procedures

---

## Helper Scripts

All provisioning and management scripts are located in:
```
scripts/tenant-provisioning/
```

**Key Scripts:**

| Script | Purpose |
|--------|---------|
| `provision-tenant.sh` | All-in-one tenant provisioning |
| `validate-tenant-request.sh` | Validate tenant information |
| `create-keycloak-organization.sh` | Create Keycloak organization |
| `create-tenant-database.sh` | Create PostgreSQL database |
| `run-tenant-schema-migration.sh` | Run Liquibase migrations |
| `load-tenant-config.sh` | Load Fineract configuration |
| `create-tenant-admin-user.sh` | Create admin user |
| `test-tenant-access.sh` | Validate tenant functionality |

See [scripts/tenant-provisioning/README.md](../../scripts/tenant-provisioning/README.md) for details.

---

## Architecture Diagrams

The architecture document includes comprehensive Mermaid diagrams:

1. **Overall System Architecture**
   - User access layer
   - Ingress layer (NGINX with wildcard DNS)
   - Authentication layer (OAuth2 Proxy + Keycloak)
   - Application layer (Fineract pods)
   - Data layer (PostgreSQL, Redis, S3)

2. **Authentication Flow**
   - JWT token flow with tenant resolution
   - Keycloak organization membership validation
   - OAuth2 Proxy session management
   - Tenant claim extraction and validation

3. **Keycloak Organizations Configuration**
   - Organizations structure
   - User-to-organization mapping
   - Protocol mappers (organization-to-tenant)
   - OAuth2 client configuration

4. **Database Architecture**
   - Shared RDS instance
   - Multiple tenant databases
   - Connection pool management
   - HikariCP configuration

5. **Request Flow**
   - Subdomain extraction
   - Authentication check
   - JWT validation
   - Database routing
   - Cache and storage access

---

## Implementation Phases

### Phase 0: Pre-Implementation Setup (1 day)
- Environment preparation
- Backup current configuration
- Prerequisites checklist
- Documentation review

### Phase 1: Keycloak Multi-Tenant Setup (2-3 days)
- Enable Organizations feature
- Create multi-tenant realm
- Configure protocol mappers
- Create test organizations and users
- Validate JWT tokens

### Phase 2: Database Multi-Tenant Configuration (2-3 days)
- Update Terraform (if needed)
- Create database scripts
- Test database creation
- Create schema migration scripts
- Test migrations

### Phase 3: Application Layer Changes (3-5 days)
- Update Fineract deployments
- Configure multi-tenant environment variables
- Update connection pool settings
- Test database connectivity
- Deploy changes

### Phase 4: Ingress and Routing (2-3 days)
- Configure wildcard DNS
- Set up wildcard TLS certificates
- Create multi-tenant ingress
- Update OAuth2 Proxy
- Test routing

### Phase 5: Testing and Validation (3-5 days)
- End-to-end testing
- Tenant isolation verification
- Performance testing
- Security testing
- Monitoring validation

### Phase 6: Migration of Default Tenant (1-2 days)
- Backup existing data
- Migrate to tenant1
- Update users and permissions
- Deprecate old setup
- Verify migration

**Total Duration:** 14-22 days

---

## Security Considerations

### Tenant Isolation

| Layer | Mechanism | Strength |
|-------|-----------|----------|
| Network | Subdomain routing | High |
| Authentication | Organization membership | High |
| Authorization | JWT tenant claim | High |
| Database | Separate databases | Very High |
| Cache | Key prefixing | Medium-High |
| Storage | Path prefixing | High |

### Security Checklist

- [ ] JWT validation on every request
- [ ] Subdomain matches JWT tenant claim
- [ ] Database connection uses correct tenant database
- [ ] S3 operations use tenant prefix
- [ ] Redis keys use tenant prefix
- [ ] Audit logging includes tenant context
- [ ] Rate limiting per tenant
- [ ] No cross-tenant data leakage

### Common Attack Vectors

1. **JWT Manipulation**: Mitigated by signature validation
2. **Subdomain Spoofing**: Mitigated by ingress validation
3. **SQL Injection**: Mitigated by separate databases + parameterized queries
4. **Cache Poisoning**: Mitigated by tenant-prefixed keys
5. **S3 Path Traversal**: Mitigated by path sanitization + IAM policies

---

## Cost Analysis

### Monthly Infrastructure Costs (50 tenants)

| Component | Cost |
|-----------|------|
| EKS Cluster | $73 |
| EKS Nodes (3× m5.xlarge) | $460 |
| RDS PostgreSQL (db.m5.2xlarge) | $560 |
| RDS Storage (500 GB) | $60 |
| RDS Backups | $48 |
| S3 Storage | $2 |
| ALB/NLB | $23 |
| CloudWatch | $50 |
| **Total** | **$1,276/month** |

**Per-Tenant Cost:** $25.52/month (at 50 tenants)

### Cost Optimization

- Use Reserved Instances: 40% savings
- S3 Lifecycle policies: 90% savings on old data
- Auto-scaling: Scale down non-prod environments
- Spot instances for batch jobs: 70% savings

---

## Monitoring and Observability

### Metrics to Track

**Per-Tenant Metrics:**
- Request rate and latency
- Error rate
- Database connections
- Cache hit rate
- S3 operations
- Storage usage

**System-Wide Metrics:**
- Total tenant count
- Active users across all tenants
- RDS CPU and memory
- Connection pool utilization
- Total storage usage

### Logging Strategy

**Log Format:**
```json
{
  "timestamp": "2025-11-24T10:30:45Z",
  "level": "INFO",
  "tenant": "tenant1",
  "user": "john.doe@tenant1.com",
  "message": "Client created successfully",
  "client_id": 123
}
```

**Log Queries:**
```sql
-- CloudWatch Logs Insights
fields @timestamp, tenant, level, message, user
| filter tenant = "tenant1" and level = "ERROR"
| sort @timestamp desc
| limit 100
```

---

## Disaster Recovery

### Backup Strategy

**RDS Automated Backups:**
- Daily snapshots (30-day retention)
- Point-in-time recovery (5-minute granularity)
- Cross-region replication (production)

**Per-Tenant Backup:**
```bash
# Backup single tenant
pg_dump -h $RDS_HOST -U $DB_USER -d fineract_tenant1 \
  --format=custom --compress=9 \
  --file=tenant1-backup-$(date +%Y%m%d).dump
```

**S3 Document Backups:**
- Versioning enabled
- Cross-region replication
- Lifecycle policy: 90-day retention

### Restore Procedures

**Restore Single Tenant:**
1. Create new database for restored tenant
2. Restore from dump file
3. Update tenant registry
4. Test restored tenant
5. Swap databases if successful

**RTO/RPO Targets:**
- Recovery Time Objective (RTO): 15 minutes
- Recovery Point Objective (RPO): 5 minutes
- Tenant isolation: Single tenant failure doesn't affect others

---

## Capacity Planning

### RDS Instance Sizing

| Instance | vCPUs | RAM | Max Connections | Recommended Tenants | Cost/Month |
|----------|-------|-----|-----------------|---------------------|------------|
| db.t3.medium | 2 | 4 GB | 150 | 5-10 (dev) | $60 |
| db.m5.large | 2 | 8 GB | 200 | 10-20 | $140 |
| db.m5.xlarge | 4 | 16 GB | 500 | 30-50 | $280 |
| db.m5.2xlarge | 8 | 32 GB | 1000 | 60-100 | $560 |
| db.m5.4xlarge | 16 | 64 GB | 2000 | 100-200 | $1,120 |

### Connection Pool Allocation

```
Per Tenant: 15 connections (5 min, 15 max)
Per Pod: 15 × 3 tenants = 45 connections
Total Pods: 7 (3 read + 3 write + 1 batch)
Total Connections: 7 × 45 = 315 connections

Recommendation: db.m5.xlarge (500 max) for 30-50 tenants
```

### Storage Scaling

**Per-Tenant Database Size:**
- Small (< 1K clients): 500 MB - 1 GB
- Medium (1K - 10K clients): 1 GB - 5 GB
- Large (10K+ clients): 5 GB - 20 GB

**Example Capacity:**
- 100 GB storage: 50 small OR 20 medium OR 5 large tenants
- Auto-scaling to 1 TB: 500+ small tenants

---

## Troubleshooting

### Common Issues

**1. JWT token missing tenant claim**
- **Cause:** User not in organization or mapper misconfigured
- **Fix:** Verify organization membership, check protocol mapper

**2. Database connection pool exhausted**
- **Cause:** Too many tenants or too many connections per pool
- **Fix:** Increase RDS instance size or reduce connections per pool

**3. Wildcard certificate not issued**
- **Cause:** DNS challenge failed or DNS not configured
- **Fix:** Verify DNS configuration, check cert-manager logs

**4. Cross-tenant access not blocked**
- **Cause:** Missing tenant validation in application
- **Fix:** Add tenant claim validation logic

### Debugging Commands

```bash
# Check Fineract logs with tenant context
kubectl logs -n fineract-dev -l app=fineract --tail=100 | grep "tenant="

# Check database connections per tenant
kubectl exec -it psql-pod -- psql -c "SELECT datname, numbackends FROM pg_stat_database WHERE datname LIKE 'fineract_%';"

# Check Redis keys per tenant
kubectl exec -it fineract-redis-0 -- redis-cli KEYS "tenant1:*"

# Check S3 objects per tenant
aws s3 ls s3://fineract-documents/tenant1/ --recursive
```

---

## Support and Contributing

### Getting Help

- **Documentation Issues:** Open issue in GitHub repository
- **Implementation Questions:** Contact platform team
- **Security Concerns:** Email security@example.com
- **Urgent Issues:** PagerDuty escalation

### Contributing

Improvements to this documentation are welcome:

1. Fork repository
2. Create feature branch
3. Make changes
4. Test documentation accuracy
5. Submit pull request

### Documentation Maintenance

- **Review Frequency:** Quarterly
- **Update Triggers:**
  - Architecture changes
  - New features added
  - Security updates
  - Process improvements

---

## Change Log

### Version 1.0 (2025-11-24)
- Initial release
- Complete multi-tenant architecture documentation
- Implementation guide with 6 phases
- Tenant provisioning operational guide
- Helper scripts for automation
- Mermaid diagrams for all major components
- Cost analysis and capacity planning
- Security considerations and threat model
- Disaster recovery procedures

---

## Next Steps

### After Reading This Documentation

1. **Architects:**
   - Review architecture decisions with stakeholders
   - Plan implementation timeline
   - Allocate resources and budget

2. **Implementation Teams:**
   - Set up development environment
   - Create implementation plan
   - Begin Phase 0

3. **Operations Teams:**
   - Review provisioning procedures
   - Set up monitoring and alerting
   - Prepare on-call procedures

### Future Enhancements

Potential improvements not covered in v1.0:

- **Automated Tenant Provisioning:** API/UI for self-service
- **Tenant Tiering:** Free/Standard/Enterprise plans with different limits
- **Multi-Region Deployment:** Tenant data in different regions
- **Advanced Monitoring:** Per-tenant Grafana dashboards
- **Cost Allocation:** Detailed per-tenant cost tracking
- **Tenant Migration:** Move tenants between RDS instances
- **Horizontal Sharding:** Multiple RDS instances for > 200 tenants

---

## Glossary

**Tenant:** An isolated customer/organization in the multi-tenant system

**Organization:** Keycloak concept for grouping users and resources

**JWT Claim:** Data embedded in JSON Web Token (e.g., tenant ID)

**Connection Pool:** Pre-established database connections for performance

**Sync Wave:** ArgoCD concept for ordered deployment

**IRSA:** IAM Roles for Service Accounts (AWS-specific)

**RDS:** Amazon Relational Database Service

**HikariCP:** Java connection pool library used by Fineract

**Liquibase:** Database schema migration tool

---

**Document Version:** 1.0
**Last Updated:** 2025-11-24
**Maintained By:** Platform Team
**Status:** ✅ Complete and Ready for Use
