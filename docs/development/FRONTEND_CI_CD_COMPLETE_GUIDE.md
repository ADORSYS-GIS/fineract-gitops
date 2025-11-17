# Complete Fineract Frontend Apps CI/CD Implementation

## Summary of Work Completed

### ✅ GitOps Repository (`fineract-gitops`) - COMPLETE

**Files Created:**
1. `apps/fineract-web-apps/base/deployment-admin.yaml`
2. `apps/fineract-web-apps/base/deployment-account-manager.yaml`
3. `apps/fineract-web-apps/base/deployment-branch-manager.yaml`  
4. `apps/fineract-web-apps/base/deployment-cashier.yaml`
5. `apps/fineract-web-apps/base/service.yaml` (all 4 services)
6. `apps/fineract-web-apps/base/configmap-nginx.yaml`
7. `apps/fineract-web-apps/base/configmap-runtime-env.yaml`
8. `apps/fineract-web-apps/base/kustomization.yaml`

**Files Updated:**
- `apps/apache-gateway/base/configmap-routing.yaml` - Added frontend routes with OIDC

**Status:** ✅ Committed to main branch

---

## Remaining Implementation Tasks

### Task 1: Create Dockerfiles in `[FINERACT_APPS_REPO_ROOT]`

Run the provided setup script or create manually:

```bash
cd [FINERACT_APPS_REPO_ROOT]
```

Or create each Dockerfile manually (4 files needed - see templates below).

---

### Task 2: Create CI/CD Workflows in `[FINERACT_APPS_REPO_ROOT]/.github/workflows`

#### File 1: `ci-frontend-apps.yml`

```yaml
name: Frontend Apps CI

on:
  push:
    branches: [main, develop]
    paths:
      - 'frontend/**'
      - 'packages/**'
      - '.github/workflows/ci-frontend-apps.yml'
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: pnpm/action-setup@v4
        with:
          version: 8
      
      - uses: actions/setup-node@v5
        with:
          node-version: 22
          cache: 'pnpm'
      
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm test:coverage
      - run: pnpm build
```

#### File 2: `publish-frontend-images.yml`

```yaml
name: Publish Frontend Docker Images

on:
  push:
    branches: [develop, main]
    paths:
      - 'frontend/**'
      - 'Dockerfile.*'
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    strategy:
      matrix:
        app: [admin, account-manager, branch-manager, cashier]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile.${{ matrix.app }}
          push: true
          tags: |
            ghcr.io/adorsys-gis/fineract-${{ matrix.app }}-app:${{ github.ref_name }}
            ghcr.io/adorsys-gis/fineract-${{ matrix.app }}-app:${{ github.sha }}
```

---

### Task 3: Quick Implementation Steps

```bash
# 1. Switch to frontend apps repo
cd [FINERACT_APPS_REPO_ROOT]

# 2. Create feature branch
git checkout -b feature/add-ci-cd-pipeline

# 3. Create Dockerfiles (run script or manual)
# ... create 4 Dockerfiles ...

# 4. Create CI/CD workflows  
mkdir -p .github/workflows
# ... create workflow files ...

# 5. Commit and push
git add .
git commit -m "feat: add Docker and CI/CD configuration for frontend apps"
git push origin feature/add-ci-cd-pipeline

# 6. Create Pull Request
gh pr create --title "Add CI/CD pipeline for frontend apps" \
  --body "Implements Docker images and CI/CD automation for all 4 frontend apps"

# 7. Configure GitHub Secret
# Go to: https://github.com/ADORSYS-GIS/fineract-apps/settings/secrets/actions
# Add: GITOPS_PAT (same token used for Fineract backend)
```

---

## Dockerfile Templates

### `Dockerfile.admin`
```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY frontend/admin-app/ ./frontend/admin-app/
RUN corepack enable pnpm && pnpm install --frozen-lockfile
RUN pnpm --filter admin-app build

FROM nginx:alpine
COPY --from=builder /app/frontend/admin-app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### `Dockerfile.account-manager`
```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY frontend/account-manager-app/ ./frontend/account-manager-app/
RUN corepack enable pnpm && pnpm install --frozen-lockfile
RUN pnpm --filter account-manager-app build

FROM nginx:alpine
COPY --from=builder /app/frontend/account-manager-app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### `Dockerfile.branch-manager`
```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY frontend/branchmanager-app/ ./frontend/branchmanager-app/
RUN corepack enable pnpm && pnpm install --frozen-lockfile
RUN pnpm --filter branchmanager-app build

FROM nginx:alpine
COPY --from=builder /app/frontend/branchmanager-app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### `Dockerfile.cashier`
```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY frontend/cashier-app/ ./frontend/cashier-app/
RUN corepack enable pnpm && pnpm install --frozen-lockfile
RUN pnpm --filter cashier-app build

FROM nginx:alpine
COPY --from=builder /app/frontend/cashier-app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Testing the Implementation

### 1. Test Docker Build Locally
```bash
cd [FINERACT_APPS_REPO_ROOT]

# Build admin app
docker build -f Dockerfile.admin -t fineract-admin-app:test .

# Test run
docker run -p 8080:80 fineract-admin-app:test

# Open browser: http://localhost:8080
```

### 2. Test CI/CD Pipeline
```bash
# Push to develop triggers:
# 1. CI tests
# 2. Docker image builds  
# 3. Push to GHCR
# 4. (Future) GitOps repo update

git push origin develop
```

### 3. Verify Images in GHCR
```
https://github.com/orgs/ADORSYS-GIS/packages
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Browser                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Apache Gateway                               │
│                                                                  │
│  - OIDC Authentication (Keycloak)                               │
│  - Route Proxying                                               │
│  - Security Headers                                             │
└────────┬──────────┬──────────┬──────────┬──────────────────────┘
         │          │          │          │
         ▼          ▼          ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
    │ Admin  │ │ AcctMgr│ │BranchMgr│ │Cashier│
    │  App   │ │  App   │ │  App   │ │  App  │
    │(Nginx) │ │(Nginx) │ │(Nginx) │ │(Nginx)│
    └────────┘ └────────┘ └────────┘ └────────┘
         │          │          │          │
         └──────────┴──────────┴──────────┘
                     │
                     ▼
            ┌────────────────┐
            │  Fineract API  │
            │ (Read/Write)   │
            └────────────────┘
```

---

## Deployment Flow

### Development
```
Commit → CI Tests → Build Images → Push to GHCR → 
Manual Deploy (for now) → ArgoCD Sync → Kubernetes
```

### Production (Future)
```
Tag Release → Build Versioned Images → GitHub Release →
Manual GitOps Update → ArgoCD Sync → Production Deploy
```

---

## Files Summary

**GitOps Repo** (✅ Complete):
- 9 Kubernetes manifest files
- 1 Apache Gateway update

**Frontend Apps Repo** (⏳ Remaining):
- 4 Dockerfiles
- 2 GitHub Actions workflows
- 1 README update

**Total Implementation Time**: ~1-2 hours

---

## Next Steps

1. ✅ GitOps manifests complete (committed)
2. ⏳ Create Dockerfiles in frontend apps repo
3. ⏳ Create CI/CD workflows
4. ⏳ Test Docker builds locally
5. ⏳ Push and test CI/CD
6. ⏳ Configure GITOPS_PAT secret
7. ⏳ Deploy to development environment
8. ⏳ Test OIDC authentication flow
9. ⏳ Verify API calls to Fineract
10. ⏳ Production deployment

---

**Status**: GitOps manifests complete and committed. Ready for Docker/CI-CD implementation in frontend apps repository.

