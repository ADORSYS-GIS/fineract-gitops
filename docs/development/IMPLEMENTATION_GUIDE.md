# Fineract GitOps Implementation Guide

This guide explains how to complete the implementation of the Fineract GitOps repository. The foundation has been created, and this document provides instructions for extending it.

## 📦 What's Already Created

### ✅ Foundation Structure
- Complete directory tree for all components
- Base Kubernetes manifests for Fineract (read/write instances)
- JSON schemas for validation (loan-product, office)
- Example YAML files (personal-loan, head-office, gender code values, loan-processing-fee)
- README.md with complete architecture documentation

### 🏗️ Repository Structure

```
fineract-gitops/
├── README.md ✅                       # Complete documentation
├── IMPLEMENTATION_GUIDE.md ✅         # This file
│
├── environments/ ✅                    # Directory structure created
│   ├── dev/
│   ├── uat/
│   └── production/
│
├── apps/ ✅                            # Partial implementation
│   ├── fineract/                      # ✅ Base deployments created
│   │   ├── base/
│   │   │   ├── deployment-read.yaml ✅
│   │   │   ├── deployment-write.yaml ✅
│   │   │   └── kustomization.yaml ✅
│   │   └── overlays/
│   │       ├── dev/ ⚠️ (needs patches)
│   │       ├── uat/ ⚠️ (needs patches)
│   │       └── production/ ⚠️ (needs patches)
│   │
│   ├── apache-gateway/ ⚠️              # Needs implementation
│   ├── keycloak/ ⚠️
│   ├── redis/ ⚠️
│   ├── minio/ ⚠️
│   ├── kafka/ ⚠️
│   └── postgresql/ ⚠️
│
├── operations/ ✅ ⚠️                    # Partial implementation
│   └── fineract-data/
│       ├── schemas/ ✅                 # 2 schemas created (need 22 more)
│       │   ├── loan-product.schema.json ✅
│       │   └── office.schema.json ✅
│       │
│       ├── data/ ✅ ⚠️                 # 4 YAML files created (need 100+)
│       │   ├── base/
│       │   │   └── codes-and-values/
│       │   │       └── gender.yaml ✅
│       │   └── dev/
│       │       ├── offices/
│       │       │   └── head-office.yaml ✅
│       │       ├── products/
│       │       │   └── loan-products/
│       │       │       └── personal-loan.yaml ✅
│       │       └── charges/
│       │           └── loan-processing-fee.yaml ✅
│       │
│       ├── jobs/ ⚠️                    # Needs implementation
│       ├── cronjobs/ ⚠️                # Needs implementation
│       └── scripts/ ⚠️                 # Needs implementation
│
└── (other directories) ⚠️              # Needs implementation
```

**Legend:**
- ✅ = Complete
- ⚠️ = Needs implementation
- Blank = Not started

## 🎯 Implementation Roadmap

### Phase 1: Core Data YAMLs (Priority 1)

#### 1.1 Create Remaining JSON Schemas

Create these 22 additional schemas in `operations/fineract-data/schemas/`:

```bash
# Product schemas
savings-product.schema.json
charge.schema.json
collateral-type.schema.json
guarantor-type.schema.json
floating-rate.schema.json

# Accounting schemas
gl-account.schema.json
fund-source.schema.json
payment-type.schema.json
tax-group.schema.json

# Configuration schemas
holiday.schema.json
staff.schema.json
role-permission.schema.json
configuration.schema.json
data-table.schema.json
notification-template.schema.json
scheduler-job.schema.json

# Entity schemas
client.schema.json
loan-account.schema.json
savings-account.schema.json

# Transaction schemas
transaction.schema.json
collateral-assignment.schema.json
guarantor-assignment.schema.json

# Reports
report-config.schema.json
```

**Template for each schema:**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Fineract [EntityType]",
  "description": "Schema for [entity description]",
  "type": "object",
  "required": ["apiVersion", "kind", "metadata", "spec"],
  "properties": {
    "apiVersion": {
      "type": "string",
      "enum": ["fineract.apache.org/v1"]
    },
    "kind": {
      "type": "string",
      "enum": ["[EntityType]"]
    },
    "metadata": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": {"type": "string", "pattern": "^[a-z0-9-]+$"},
        "labels": {"type": "object"}
      }
    },
    "spec": {
      "type": "object",
      "required": [],  // Add required fields
      "properties": {
        // Add entity-specific properties
      }
    }
  }
}
```

#### 1.2 Create Base Code Values

Create YAML files in `operations/fineract-data/data/base/codes-and-values/`:

```yaml
# Example: client-type.yaml
apiVersion: fineract.apache.org/v1
kind: CodeValue
metadata:
  name: client-type

spec:
  codeName: ClientType
  description: Type of client

  values:
    - name: Individual
      position: 1
      active: true

    - name: Corporate
      position: 2
      active: true
```

**Code values to create:**
- client-type.yaml ✅ (gender done)
- client-classification.yaml
- marital-status.yaml
- education-level.yaml
- employment-status.yaml
- loan-purpose.yaml
- id-type.yaml
- relationship-type.yaml
- business-type.yaml
- risk-rating.yaml

#### 1.3 Create Dev Environment Data

For each entity type, create example YAML files in `operations/fineract-data/data/dev/`:

**Products:**
```
products/
├── loan-products/
│   ├── personal-loan.yaml ✅
│   ├── business-loan.yaml
│   ├── emergency-loan.yaml
│   └── agricultural-loan.yaml
│
└── savings-products/
    ├── basic-savings.yaml
    ├── fixed-deposit.yaml
    └── current-account.yaml
```

**Use your existing Excel data** from `docs/data-collection/fineract-demo-data/` to populate these YAML files.

**Conversion approach:**
1. Read Excel sheet
2. For each row, create a YAML file
3. Map Excel columns to YAML spec properties

**Example mapping:**

| Excel Column | YAML Path |
|--------------|-----------|
| Product Name | spec.name |
| Min Principal | spec.principal.min |
| Max Principal | spec.principal.max |
| Interest Rate | spec.interestRate.default |

### Phase 2: Kubernetes Manifests (Priority 2)

#### 2.1 Complete Fineract Manifests

Add these files to `apps/fineract/base/`:

```yaml
# service-read.yaml
apiVersion: v1
kind: Service
metadata:
  name: fineract-read-service
spec:
  selector:
    app: fineract-read
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP

---
# service-write.yaml
apiVersion: v1
kind: Service
metadata:
  name: fineract-write-service
spec:
  selector:
    app: fineract-write
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP

---
# deployment-batch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-batch
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fineract-batch
  template:
    metadata:
      labels:
        app: fineract-batch
    spec:
      containers:
      - name: fineract
        image: apache/fineract:latest
        env:
        - name: FINERACT_MODE_BATCH_WORKER_ENABLED
          value: "true"
        - name: FINERACT_MODE_BATCH_MANAGER_ENABLED
          value: "true"
        # ... other env vars similar to read/write

---
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fineract-config
data:
  application.properties: |
    # Fineract configuration
    fineract.tenant.default.name=default
    # ... other properties

---
# hpa-read.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fineract-read-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fineract-read
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

#### 2.2 Create Environment Overlays

For each environment, create patch files:

```yaml
# apps/fineract/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: fineract-dev

resources:
- ../../base

patchesStrategicMerge:
- replica-patch.yaml
- resource-patch.yaml

configMapGenerator:
- name: env-config
  literals:
  - ENVIRONMENT=dev
  - LOG_LEVEL=DEBUG

images:
- name: apache/fineract
  newTag: dev-latest

---
# apps/fineract/overlays/dev/replica-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-read
spec:
  replicas: 1

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fineract-write
spec:
  replicas: 1
```

**Repeat for production** with higher replicas (10 read, 2 write, 5 batch).

#### 2.3 Create Apache Gateway Manifests

```yaml
# apps/apache-gateway/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: apache-gateway
  template:
    metadata:
      labels:
        app: apache-gateway
      annotations:
        reloader.stakater.com/auto: "true"
    spec:
      containers:
      - name: apache
        image: httpd:2.4-alpine
        ports:
        - containerPort: 80
        - containerPort: 443
        volumeMounts:
        - name: apache-config
          mountPath: /usr/local/apache2/conf/httpd.conf
          subPath: httpd.conf
        - name: proxy-config
          mountPath: /usr/local/apache2/conf/extra/proxy.conf
          subPath: proxy.conf
      volumes:
      - name: apache-config
        configMap:
          name: apache-config
      - name: proxy-config
        configMap:
          name: apache-proxy-config

---
# apps/apache-gateway/base/configmap-proxy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: apache-proxy-config
data:
  proxy.conf: |
    # Read operations to read instances
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^GET$
    RewriteRule ^/fineract/api/v1/(.*)$ http://fineract-read-service:8080/fineract-provider/api/v1/$1 [P,L]

    # Write operations to write instance
    RewriteCond %{REQUEST_METHOD} ^(POST|PUT|DELETE|PATCH)$
    RewriteRule ^/fineract/api/v1/(.*)$ http://fineract-write-service:8080/fineract-provider/api/v1/$1 [P,L]
```

### Phase 3: Data Loading Jobs (Priority 3)

#### 3.1 Create Sequential Loading Jobs

```yaml
# operations/fineract-data/jobs/base/01-load-configurations.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: load-configurations
spec:
  template:
    spec:
      containers:
      - name: config-loader
        image: your-registry/fineract-data-loader:latest
        command:
        - python3
        - /scripts/loaders/configurations.py
        - --yaml-dir
        - /data/system-config
        - --fineract-url
        - http://fineract-write-service:8080/fineract-provider/api/v1
        volumeMounts:
        - name: config-data
          mountPath: /data
        env:
        - name: FINERACT_USERNAME
          valueFrom:
            secretKeyRef:
              name: fineract-admin-credentials
              key: username
        - name: FINERACT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fineract-admin-credentials
              key: password
      volumes:
      - name: config-data
        projected:
          sources:
          - configMap:
              name: system-config-data
      restartPolicy: OnFailure
      backoffLimit: 3
```

**Create 30 jobs in sequence:**

1. load-configurations
2. load-code-values
3. load-offices
4. load-staff
5. load-roles-permissions
6. load-chart-of-accounts
7. load-fund-sources
8. load-payment-types
9. load-holidays
10. load-loan-provisioning
11. load-collateral-types
12. load-guarantor-types
13. load-floating-rates
14. load-delinquency-buckets
15. load-tax-groups
16. load-charges
17. load-loan-products
18. load-savings-products
19. load-product-accounting
20. load-tellers
21. load-scheduler-jobs
22. load-notifications
23. load-data-tables
24. load-reports
25. load-clients (dev/uat only)
26. load-loan-accounts (dev/uat only)
27. load-savings-accounts (dev/uat only)
28. load-collateral (dev/uat only)
29. load-guarantors (dev/uat only)
30. load-transactions (dev/uat only)

#### 3.2 Create Python Loader Scripts

**Base loader class:**

```python
# operations/fineract-data/scripts/loaders/base_loader.py
import os
import yaml
import requests
from pathlib import Path

class BaseLoader:
    def __init__(self, yaml_dir, fineract_url):
        self.yaml_dir = Path(yaml_dir)
        self.fineract_url = fineract_url
        self.username = os.getenv('FINERACT_USERNAME')
        self.password = os.getenv('FINERACT_PASSWORD')
        self.session = requests.Session()
        self.session.auth = (self.username, self.password)

    def load_yaml(self, filepath):
        """Load and parse YAML file"""
        with open(filepath) as f:
            return yaml.safe_load(f)

    def post_to_fineract(self, endpoint, data):
        """POST data to Fineract API"""
        url = f"{self.fineract_url}/{endpoint}"
        response = self.session.post(url, json=data)
        response.raise_for_status()
        return response.json()

    def yaml_to_fineract_api(self, yaml_data):
        """Convert YAML structure to Fineract API payload"""
        # Override in subclasses
        raise NotImplementedError
```

**Product loader example:**

```python
# operations/fineract-data/scripts/loaders/loan_products.py
from base_loader import BaseLoader

class LoanProductLoader(BaseLoader):
    def yaml_to_fineract_api(self, yaml_data):
        """Convert loan product YAML to Fineract API format"""
        spec = yaml_data['spec']

        return {
            'name': spec['name'],
            'shortName': spec.get('shortName'),
            'description': spec.get('description'),
            'currencyCode': spec['currency'],
            'digitsAfterDecimal': spec.get('digitsAfterDecimal', 2),
            'inMultiplesOf': spec.get('inMultiplesOf'),
            'principal': spec['principal']['default'],
            'minPrincipal': spec['principal']['min'],
            'maxPrincipal': spec['principal']['max'],
            'numberOfRepayments': spec['numberOfRepayments']['default'],
            'minNumberOfRepayments': spec['numberOfRepayments']['min'],
            'maxNumberOfRepayments': spec['numberOfRepayments']['max'],
            'repaymentEvery': spec['repaymentEvery'],
            'repaymentFrequencyType': self.map_frequency(spec['repaymentFrequency']),
            'interestRatePerPeriod': spec['interestRate']['default'],
            'minInterestRatePerPeriod': spec['interestRate']['min'],
            'maxInterestRatePerPeriod': spec['interestRate']['max'],
            'interestType': self.map_interest_type(spec['interestRate']['type']),
            # ... map all other fields
        }

    def map_frequency(self, freq):
        mapping = {
            'DAYS': 0,
            'WEEKS': 1,
            'MONTHS': 2,
            'YEARS': 3
        }
        return mapping.get(freq, 2)

    def load_all(self):
        """Load all loan products from YAML directory"""
        for yaml_file in self.yaml_dir.glob('**/*.yaml'):
            yaml_data = self.load_yaml(yaml_file)
            if yaml_data.get('kind') == 'LoanProduct':
                api_data = self.yaml_to_fineract_api(yaml_data)
                result = self.post_to_fineract('loanproducts', api_data)
                print(f"✓ Loaded: {spec['name']}")

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--yaml-dir', required=True)
    parser.add_argument('--fineract-url', required=True)
    args = parser.parse_args()

    loader = LoanProductLoader(args.yaml_dir, args.fineract_url)
    loader.load_all()
```

**Create similar loaders for all 30 entity types**.

### Phase 4: ArgoCD Configuration (Priority 4)

#### 4.1 Create ArgoCD Projects

```yaml
# argocd/projects/dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: fineract-dev
  namespace: argocd
spec:
  description: Fineract Development Environment

  sourceRepos:
  - 'https://github.com/your-org/fineract-gitops'

  destinations:
  - namespace: 'fineract-dev'
    server: 'https://kubernetes.default.svc'

  clusterResourceWhitelist:
  - group: ''
    kind: Namespace

  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
```

#### 4.2 Create App-of-Apps

```yaml
# argocd/applications/dev/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fineract-dev
  namespace: argocd
spec:
  project: fineract-dev

  source:
    repoURL: https://github.com/your-org/fineract-gitops
    targetRevision: main
    path: environments/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: fineract-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Phase 5: Validation & Scripts (Priority 5)

#### 5.1 Create Validation Script

```python
# scripts/validate-data.py
#!/usr/bin/env python3
import sys
import yaml
import jsonschema
import json
from pathlib import Path

def validate_yaml_file(yaml_file, schema_file):
    try:
        with open(yaml_file) as f:
            data = yaml.safe_load(f)

        with open(schema_file) as f:
            schema = json.load(f)

        jsonschema.validate(instance=data, schema=schema)
        print(f"✓ {yaml_file} is valid")
        return True
    except Exception as e:
        print(f"✗ {yaml_file}: {e}")
        return False

# Map YAML kinds to schema files
SCHEMA_MAP = {
    'LoanProduct': 'loan-product.schema.json',
    'Office': 'office.schema.json',
    # ... add all mappings
}

def main():
    data_dir = Path("operations/fineract-data/data")
    schema_dir = Path("operations/fineract-data/schemas")
    errors = []

    for yaml_file in data_dir.glob('**/*.yaml'):
        with open(yaml_file) as f:
            data = yaml.safe_load(f)

        kind = data.get('kind')
        if kind in SCHEMA_MAP:
            schema_file = schema_dir / SCHEMA_MAP[kind]
            if not validate_yaml_file(yaml_file, schema_file):
                errors.append(yaml_file)

    if errors:
        print(f"\n❌ Validation failed for {len(errors)} file(s)")
        sys.exit(1)
    else:
        print(f"\n✅ All files validated successfully")
        sys.exit(0)

if __name__ == "__main__":
    main()
```

#### 5.2 Create Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash
set -e

echo "🔍 Validating YAML configuration files..."
python3 scripts/validate-data.py

echo "✅ Pre-commit checks passed"
```

### Phase 6: Documentation (Priority 6)

Create comprehensive documentation in `docs/`:

1. **Architecture**:
   - `architecture/overview.md`
   - `architecture/security-model.md`
   - `architecture/disaster-recovery.md`

2. **Operations**:
   - `operations/runbooks/incident-response.md`
   - `operations/runbooks/database-failover.md`
   - `operations/runbooks/scaling-procedures.md`
   - `operations/sop/daily-operations.md`

3. **Development**:
   - `development/local-development.md`
   - `development/contributing.md`
   - `development/plugin-development.md`

4. **Compliance**:
   - `compliance/audit-logging.md`
   - `compliance/data-retention.md`
   - `compliance/regulatory-requirements.md`

## 🎬 Getting Started

### Quick Start for Developers

1. **Use existing Excel data**:
   ```bash
   # Your existing Excel file
   ls docs/data-collection/fineract-demo-data/fineract_demo_data.xlsx
   ```

2. **Convert Excel to YAML**:
   - Manually create YAML files based on Excel data
   - OR write a conversion script
   - Use the examples already created as templates

3. **Validate**:
   ```bash
   python3 scripts/validate-data.py
   ```

4. **Deploy to dev**:
   ```bash
   kubectl apply -f argocd/applications/dev/app-of-apps.yaml
   ```

## 📋 Checklist for Complete Implementation

### Data Layer
- [ ] Create all 24 JSON schemas
- [ ] Create all base code values (10 files)
- [ ] Create dev environment data (100+ YAML files)
- [ ] Create UAT environment data (copy from dev, modify)
- [ ] Create production environment data (config only, no demo data)

### Kubernetes Layer
- [ ] Complete Fineract manifests (services, HPA, configmaps)
- [ ] Create environment overlays (dev/uat/prod)
- [ ] Implement Apache Gateway
- [ ] Implement Keycloak
- [ ] Implement Redis
- [ ] Implement MinIO
- [ ] Implement Kafka
- [ ] Implement PostgreSQL
- [ ] Create frontend app manifests (5 apps)
- [ ] Create plugin manifests (4 plugins)
- [ ] Create platform services (observability, security, backup)

### Operations Layer
- [ ] Create 30 data loading jobs
- [ ] Create 30 Python loader scripts
- [ ] Create CronJobs for scheduled operations
- [ ] Create drift detection job
- [ ] Create backup jobs

### GitOps Layer
- [ ] Create ArgoCD projects (dev/uat/prod)
- [ ] Create app-of-apps for each environment
- [ ] Create individual application manifests
- [ ] Configure sync policies
- [ ] Configure RBAC

### Automation Layer
- [ ] Create validation script
- [ ] Create YAML-to-API converter
- [ ] Create export-to-YAML script
- [ ] Create promotion script
- [ ] Create rollback script
- [ ] Create pre-commit hooks

### Infrastructure Layer
- [ ] Create Terraform modules
- [ ] Create environment-specific Terraform configs
- [ ] Document infrastructure provisioning

### Documentation Layer
- [ ] Architecture documentation
- [ ] Operations runbooks
- [ ] Development guide
- [ ] Compliance documentation
- [ ] API documentation

## 🚀 Recommended Implementation Order

1. **Week 1**: Complete data layer (schemas + YAMLs)
2. **Week 2**: Complete Kubernetes manifests
3. **Week 3**: Create data loading jobs + scripts
4. **Week 4**: ArgoCD configuration + testing
5. **Week 5**: Automation scripts + validation
6. **Week 6**: Documentation + training

## 💡 Tips

1. **Reuse your existing work**: The Excel generator script you have can be adapted to generate YAML instead
2. **Start small**: Implement one complete entity type end-to-end first (e.g., Loan Products)
3. **Test incrementally**: Deploy to dev after each component is complete
4. **Use templates**: Copy and modify existing YAML files
5. **Automate**: Write scripts to convert your Excel data to YAML

## 📞 Need Help?

- Review the README.md for architecture overview
- Check existing YAML files for examples
- Refer to Fineract API documentation for field mappings

---

**This foundation provides the structure. Complete implementation requires filling in the templates based on your specific Fineract configuration needs.**
