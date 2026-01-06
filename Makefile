# Fineract GitOps - Automated Deployment
# Single-command deployment for the entire Fineract platform

.PHONY: help deploy destroy status test clean cleanup-cluster deploy-dev deploy-uat deploy-prod \
	deploy-infrastructure-dev deploy-k8s-with-loadbalancer-dns-dev deploy-with-loadbalancer-dns-dev \
	seal-secrets seal-terraform-secrets seal-app-secrets seal-argocd-secret \
	deploy-gitops deploy-step-1 deploy-step-2 deploy-step-3 deploy-step-4 deploy-step-5 \
	verify-namespaces validate-ingress-dns validate-prereqs validate-terraform-prereqs validate-k8s-prereqs validate-terraform setup-terraform-backend \
	terraform-init-dev terraform-init-uat terraform-init-prod \
	terraform-plan-dev terraform-plan-uat terraform-plan-prod \
	terraform-apply-dev terraform-apply-uat terraform-apply-prod \
	terraform-destroy-dev terraform-destroy-uat terraform-destroy-prod \
	terraform-output-dev terraform-output-uat terraform-output-prod

# Default environment
ENV ?= dev

# Color output
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

help:
	@echo "$(BLUE)Fineract GitOps - Automated Deployment$(NC)"
	@echo ""
	@echo "$(GREEN)📖 Documentation:$(NC)"
	@echo "  See DEPLOYMENT.md for complete deployment guide with troubleshooting"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make deploy [ENV=dev|uat|prod]  - Deploy complete Fineract stack"
	@echo "  make destroy [ENV=dev|uat|prod] - Destroy infrastructure"
	@echo "  make status [ENV=dev|uat|prod]  - Check deployment status"
	@echo "  make test [ENV=dev|uat|prod]    - Run smoke tests"
	@echo "  make clean                       - Clean up logs and temporary files"
	@echo "  make cleanup-cluster             - Force-delete stuck namespaces (use when namespaces are stuck)"
	@echo ""
	@echo "$(YELLOW)Environment-specific shortcuts:$(NC)"
	@echo "  make deploy-dev                  - Deploy to dev"
	@echo "  make deploy-uat                  - Deploy to UAT"
	@echo "  make deploy-prod                 - Deploy to production (manual approval required)"
	@echo ""
	@echo "$(YELLOW)Two-phase deployment (Recommended for fresh deployments):$(NC)"
	@echo "  make deploy-infrastructure-dev           - Phase 1: Deploy infrastructure + setup kubeconfig"
	@echo "  make deploy-k8s-with-loadbalancer-dns-dev - Phase 2: Deploy K8s resources + LoadBalancer DNS"
	@echo ""
	@echo "$(RED)⚠️  Deprecated commands (see DEPRECATIONS.md):$(NC)"
	@echo "  make deploy-with-loadbalancer-dns-dev   - ⚠️ DEPRECATED (removal: 2026-05-20) - Use two-phase deployment"
	@echo ""
	@echo "$(YELLOW)Component deployment:$(NC)"
	@echo "  make deploy-infrastructure       - Deploy AWS infrastructure only"
	@echo "  make deploy-argocd               - Deploy ArgoCD only"
	@echo "  make deploy-apps                 - Deploy applications only"
	@echo ""
	@echo "$(YELLOW)⭐ GitOps Interactive Deployment (RECOMMENDED):$(NC)"
	@echo "  make deploy-gitops               - Interactive step-by-step deployment (with confirmations)"
	@echo ""
	@echo "$(YELLOW)GitOps Individual Steps (can run independently):$(NC)"
	@echo "  make deploy-step-1               - Step 1: Validate prerequisites"
	@echo "  make deploy-step-2               - Step 2: Deploy infrastructure"
	@echo "  make deploy-step-3               - Step 3: Setup ArgoCD"
	@echo "  make deploy-step-4               - Step 4: Deploy applications"
	@echo "  make deploy-step-5               - Step 5: Verify deployment"
	@echo "  make verify-namespaces           - Verify resources in correct namespaces"
	@echo ""
	@echo "$(YELLOW)Secrets management:$(NC)"
	@echo "  make seal-secrets [ENV=dev]      - Generate all sealed secrets"
	@echo "  make seal-terraform-secrets      - Generate Terraform-managed secrets (RDS, S3)"
	@echo "  make seal-app-secrets            - Generate application secrets (Redis, Keycloak)"
	@echo "  make seal-argocd-secret          - Generate ArgoCD GitHub credentials"
	@echo ""
	@echo "$(YELLOW)Validation and prerequisites:$(NC)"
	@echo "  make validate-ingress-dns [ENV=dev] - Validate Ingress DNS matches LoadBalancer"
	@echo "  make validate-prereqs            - Validate all prerequisites (runs both checks below)"
	@echo "  make validate-terraform-prereqs  - Validate Terraform/Infrastructure prerequisites only"
	@echo "  make validate-k8s-prereqs        - Validate Kubernetes/GitOps prerequisites (includes SSH deploy key)"
	@echo ""
	@echo "$(YELLOW)Terraform workflow:$(NC)"
	@echo "  make setup-terraform-backend     - Initialize Terraform S3 backend"
	@echo "  make terraform-init-{env}        - Initialize Terraform for environment"
	@echo "  make terraform-plan-{env}        - Plan infrastructure changes"
	@echo "  make terraform-apply-{env}       - Apply infrastructure changes"
	@echo "  make terraform-destroy-{env}     - Destroy infrastructure"
	@echo "  make terraform-output-{env}      - Show Terraform outputs"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make validate-prereqs                   - ✅ Validate all prerequisites"
	@echo "  make validate-terraform-prereqs         - ✅ Validate only Terraform prerequisites"
	@echo "  make validate-k8s-prereqs               - ✅ Validate only K8s/GitOps prerequisites"
	@echo ""
	@echo "  make deploy-infrastructure-dev          - 🏗️  Phase 1: Deploy infrastructure"
	@echo "  make deploy-k8s-with-loadbalancer-dns-dev - 🌐 Phase 2: Deploy K8s + LoadBalancer DNS"
	@echo ""
	@echo "  make deploy-gitops                      - 🚀 Full interactive deployment (alternative)"
	@echo "  make deploy ENV=uat                     - Deploy UAT environment"
	@echo "  make status ENV=prod                    - Check production status"
	@echo "  make seal-secrets ENV=dev               - Generate all dev secrets"

# Full stack deployment
deploy:
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Fineract GitOps - Full Stack Deploy  $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)Environment:$(NC) $(ENV)"
	@echo "$(BLUE)Start Time:$(NC) $$(date)"
	@echo ""
	@./scripts/deploy-full-stack.sh $(ENV)

# Environment-specific deployments
deploy-dev:
	@$(MAKE) deploy ENV=dev

deploy-uat:
	@$(MAKE) deploy ENV=uat

deploy-prod:
	@echo "$(YELLOW)========================================$(NC)"
	@echo "$(YELLOW) PRODUCTION DEPLOYMENT WARNING         $(NC)"
	@echo "$(YELLOW)========================================$(NC)"
	@echo ""
	@echo "$(RED)This will deploy to PRODUCTION!$(NC)"
	@echo ""
	@read -p "Are you sure? Type 'DEPLOY_PROD' to continue: " confirm; \
	if [ "$$confirm" = "DEPLOY_PROD" ]; then \
		$(MAKE) deploy ENV=prod; \
	else \
		echo "$(RED)Deployment cancelled$(NC)"; \
		exit 1; \
	fi

# TWO-PHASE DEPLOYMENT (Recommended for fresh deployments)

# Phase 1: Infrastructure deployment (Terraform + EKS + Kubeconfig setup)
deploy-infrastructure-dev: ## Deploy infrastructure only (Terraform, EKS, RDS, S3) and setup kubeconfig
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Phase 1: Infrastructure Deployment    $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)This will:$(NC)"
	@echo "  1. Validate Terraform prerequisites"
	@echo "  2. Initialize and apply Terraform (EKS, RDS, S3, VPC)"
	@echo "  3. Setup kubeconfig with EKS cluster endpoint"
	@echo "  4. Verify kubectl connectivity"
	@echo ""
	@$(MAKE) validate-terraform-prereqs
	@echo ""
	@echo "$(YELLOW)Starting Terraform deployment...$(NC)"
	@cd terraform/aws && terraform init -backend-config=backend-dev.tfbackend -reconfigure
	@cd terraform/aws && terraform apply -var-file=environments/dev-eks.tfvars -auto-approve
	@echo ""
	@echo "$(YELLOW)Setting up kubeconfig...$(NC)"
	@./scripts/setup-eks-kubeconfig.sh dev
	@echo ""
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) ✓ Infrastructure Deployment Complete! $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)Next step:$(NC)"
	@echo "  Run: make deploy-k8s-with-loadbalancer-dns-dev"

# Phase 2: Kubernetes resources with LoadBalancer DNS (GitOps + Apps)
deploy-k8s-with-loadbalancer-dns-dev: ## Deploy K8s resources with LoadBalancer DNS auto-configuration
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Phase 2: K8s Resources + LoadBalancer $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)This will:$(NC)"
	@echo "  1. Validate K8s/GitOps prerequisites (kubectl, GITHUB_TOKEN)"
	@echo "  2. Deploy GitOps tools (ArgoCD, Sealed Secrets, ingress-nginx)"
	@echo "  3. Wait for LoadBalancer DNS provisioning"
	@echo "  4. Auto-update configurations with LoadBalancer DNS"
	@echo "  5. Deploy all applications via ArgoCD"
	@echo ""
	@$(MAKE) validate-k8s-prereqs
	@echo ""
	@echo "$(YELLOW)Deploying Kubernetes resources...$(NC)"
	@./scripts/deploy-k8s-with-loadbalancer-dns.sh dev
	@echo ""
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) ✓ Full Deployment Complete!           $(NC)"
	@echo "$(GREEN)========================================$(NC)"

# DEPRECATED: All-in-one LoadBalancer DNS deployment (archived to scripts/legacy/)
deploy-with-loadbalancer-dns-dev: ## ⚠️ DEPRECATED - Removal planned 2026-05-20 - Use two-phase deployment instead
	@echo "$(RED)╔════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(RED)║            ⚠️  DEPRECATED COMMAND  ⚠️                       ║$(NC)"
	@echo "$(RED)╚════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)This command uses a deprecated script.$(NC)"
	@echo ""
	@echo "Deprecated: $(YELLOW)2025-11-20$(NC)"
	@echo "Removal planned: $(RED)2026-05-20$(NC)"
	@echo ""
	@echo "$(GREEN)Recommended alternatives:$(NC)"
	@echo "  1. Two-phase deployment (for fresh infrastructure):"
	@echo "     $(BLUE)make deploy-infrastructure-dev$(NC)"
	@echo "     $(BLUE)make deploy-k8s-with-loadbalancer-dns-dev$(NC)"
	@echo ""
	@echo "  2. Interactive GitOps deployment:"
	@echo "     $(BLUE)make deploy-gitops$(NC)"
	@echo ""
	@echo "See $(BLUE)DEPRECATIONS.md$(NC) for details."
	@echo ""
	@read -p "Continue with deprecated command? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo ""; \
		echo "$(GREEN)Good choice! Use one of the recommended alternatives above.$(NC)"; \
		exit 0; \
	fi
	@./scripts/legacy/deploy-with-loadbalancer-dns.sh dev

# Infrastructure only
deploy-infrastructure:
	@echo "$(GREEN)Deploying infrastructure for $(ENV) environment...$(NC)"
	@./scripts/deploy-infrastructure.sh $(ENV)

# ArgoCD bootstrap
deploy-argocd:
	@echo "$(GREEN)Bootstrapping ArgoCD for $(ENV) environment...$(NC)"
	@./scripts/bootstrap-argocd.sh $(ENV)

# Applications only
deploy-apps:
	@echo "$(GREEN)Deploying applications for $(ENV) environment...$(NC)"
	@./scripts/deploy-app-of-apps.sh $(ENV)

# Destroy infrastructure
destroy:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) WARNING: DESTROYING INFRASTRUCTURE    $(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)Environment:$(NC) $(ENV)"
	@echo "$(RED)This will DELETE all resources!$(NC)"
	@echo ""
	@cd terraform/aws && ./scripts/destroy-all.sh $(ENV)

# Check deployment status
status:
	@echo "$(BLUE)Checking deployment status for $(ENV)...$(NC)"
	@./scripts/deployment-health-check.sh $(ENV)

# Run smoke tests
test:
	@echo "$(GREEN)Running smoke tests for $(ENV)...$(NC)"
	@./scripts/deployment-health-check.sh $(ENV)

# Clean up temporary files
clean:
	@echo "$(YELLOW)Cleaning up logs and temporary files...$(NC)"
	@find terraform/aws -name "*.log" -type f -delete 2>/dev/null || true
	@find scripts -name "*.log" -type f -delete 2>/dev/null || true
	@find . -name "*.tfplan" -type f -delete 2>/dev/null || true
	@rm -rf terraform/aws/.terraform/modules 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

# Force cleanup stuck Kubernetes namespaces
cleanup-cluster:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) Cluster Cleanup - Force Delete Stuck Namespaces$(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)This will:$(NC)"
	@echo "  • Remove all ArgoCD Applications"
	@echo "  • Force-delete stuck namespaces (argocd, fineract-dev, ingress-nginx, cert-manager)"
	@echo "  • Delete Custom Resource Definitions"
	@echo ""
	@echo "$(YELLOW)Use this when namespaces are stuck in 'Terminating' state.$(NC)"
	@echo ""
	@./scripts/cleanup-cluster.sh

# Sealed Secrets Management
seal-secrets:
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Generating All Sealed Secrets         $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)Environment:$(NC) $(ENV)"
	@echo ""
	@echo "$(YELLOW)Step 1: Terraform-managed secrets (RDS, S3, OAuth2)$(NC)"
	@./scripts/seal-terraform-secrets.sh $(ENV)
	@echo ""
	@echo "$(YELLOW)Step 2: Application secrets (Redis, Keycloak, Grafana)$(NC)"
	@./scripts/create-complete-sealed-secrets.sh $(ENV)
	@echo ""
	@echo "$(GREEN)✓ All sealed secrets generated!$(NC)"
	@echo ""
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Review generated secrets in secrets/$(ENV)/"
	@echo "  2. Commit to Git: git add secrets/$(ENV)/ && git commit -m 'Add sealed secrets for $(ENV)'"
	@echo "  3. Deploy: make deploy-apps ENV=$(ENV)"

seal-terraform-secrets:
	@echo "$(GREEN)Generating Terraform-managed secrets for $(ENV)...$(NC)"
	@./scripts/seal-terraform-secrets.sh $(ENV)

seal-app-secrets:
	@echo "$(GREEN)Generating application secrets for $(ENV)...$(NC)"
	@./scripts/create-complete-sealed-secrets.sh $(ENV)

seal-argocd-secret:
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Generate ArgoCD GitHub Credentials    $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)This will create a sealed secret for ArgoCD repository access.$(NC)"
	@echo ""
	@read -p "Enter GitHub Personal Access Token (PAT): " github_token; \
	./scripts/seal-argocd-github-credentials.sh $$github_token
	@echo ""
	@echo "$(GREEN)✓ ArgoCD GitHub credentials sealed!$(NC)"
	@echo "$(BLUE)Commit to Git:$(NC) git add secrets/system/ && git commit -m 'Add ArgoCD GitHub credentials'"

# Validate all prerequisites (master check)
validate-prereqs:
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE) Validating All Prerequisites          $(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@$(MAKE) validate-terraform-prereqs
	@echo ""
	@$(MAKE) validate-k8s-prereqs
	@echo ""
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) ✓ All Prerequisites Validated!        $(NC)"
	@echo "$(GREEN)========================================$(NC)"

# Validate Terraform/Infrastructure prerequisites
validate-terraform-prereqs:
	@echo "$(BLUE)Validating Terraform/Infrastructure prerequisites...$(NC)"
	@echo ""
	@# Check AWS CLI
	@command -v aws >/dev/null 2>&1 || { echo "$(RED)✗ aws CLI not found. Install: brew install awscli$(NC)" >&2; exit 1; }
	@echo "$(GREEN)✓ AWS CLI installed$(NC)"
	@# Check Terraform
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)✗ terraform not found. Install: brew install terraform$(NC)" >&2; exit 1; }
	@# Check Terraform version
	@TF_VERSION=$$(terraform version -json 2>/dev/null | grep '"terraform_version"' | sed 's/.*"terraform_version": *"\([^"]*\)".*/\1/'); \
	if [ -z "$$TF_VERSION" ]; then \
		echo "$(RED)✗ Cannot determine Terraform version$(NC)"; \
		exit 1; \
	fi; \
	REQUIRED_VERSION="1.5.0"; \
	TF_MAJOR=$$(echo $$TF_VERSION | cut -d. -f1); \
	TF_MINOR=$$(echo $$TF_VERSION | cut -d. -f2); \
	if [ $$TF_MAJOR -lt 1 ] || ([ $$TF_MAJOR -eq 1 ] && [ $$TF_MINOR -lt 5 ]); then \
		echo "$(RED)✗ Terraform version $$TF_VERSION is below required $$REQUIRED_VERSION$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓ Terraform version: $$TF_VERSION (>= $$REQUIRED_VERSION)$(NC)"
	@# Check AWS CLI configuration
	@AWS_REGION=$$(aws configure get region 2>/dev/null); \
	if [ -z "$$AWS_REGION" ]; then \
		echo "$(YELLOW)⚠ AWS region not configured. Set with: aws configure set region us-east-1$(NC)"; \
	else \
		echo "$(GREEN)✓ AWS region: $$AWS_REGION$(NC)"; \
	fi
	@# Validate AWS credentials
	@if aws sts get-caller-identity >/dev/null 2>&1; then \
		AWS_ACCOUNT=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null); \
		AWS_ARN=$$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); \
		echo "$(GREEN)✓ AWS credentials valid (Account: $$AWS_ACCOUNT)$(NC)"; \
		echo "  Identity: $$AWS_ARN"; \
	else \
		echo "$(RED)✗ AWS credentials invalid or not configured$(NC)"; \
		echo "$(YELLOW)  Configure with: aws configure$(NC)"; \
		exit 1; \
	fi
	@# Check Terraform backend bucket (if terraform is initialized)
	@if [ -f terraform/aws/.terraform/terraform.tfstate ]; then \
		BACKEND_BUCKET=$$(grep -o '"bucket":"[^"]*' terraform/aws/.terraform/terraform.tfstate 2>/dev/null | cut -d'"' -f4 || echo ""); \
		if [ -n "$$BACKEND_BUCKET" ]; then \
			if aws s3 ls s3://$$BACKEND_BUCKET >/dev/null 2>&1; then \
				echo "$(GREEN)✓ Terraform backend bucket accessible: $$BACKEND_BUCKET$(NC)"; \
			else \
				echo "$(YELLOW)⚠ Terraform backend bucket not accessible: $$BACKEND_BUCKET$(NC)"; \
			fi; \
		fi; \
	else \
		echo "$(YELLOW)⚠ Terraform not initialized yet (run 'make terraform-init-{env}')$(NC)"; \
	fi
	@echo ""
	@echo "$(GREEN)✓ All Terraform/Infrastructure prerequisites validated$(NC)"

# Validate Kubernetes/GitOps prerequisites
validate-k8s-prereqs:
	@echo "$(BLUE)Validating Kubernetes/GitOps prerequisites...$(NC)"
	@echo ""
	@# Check kubectl
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)✗ kubectl not found. Install: brew install kubectl$(NC)" >&2; exit 1; }
	@KUBECTL_VERSION=$$(kubectl version --client 2>/dev/null | grep -o 'Client Version: v[0-9.]*' | cut -d'v' -f2 || kubectl version --client -o json 2>/dev/null | grep '"gitVersion"' | sed 's/.*"gitVersion": *"v\([^"]*\)".*/\1/' || echo ""); \
	if [ -z "$$KUBECTL_VERSION" ]; then \
		echo "$(YELLOW)⚠ Cannot determine kubectl version$(NC)"; \
	else \
		echo "$(GREEN)✓ kubectl version: $$KUBECTL_VERSION$(NC)"; \
	fi
	@# Check kubeseal
	@command -v kubeseal >/dev/null 2>&1 || { echo "$(RED)✗ kubeseal not found. Install: brew install kubeseal$(NC)" >&2; exit 1; }
	@echo "$(GREEN)✓ kubeseal installed$(NC)"
	@# Check SSH
	@command -v ssh >/dev/null 2>&1 || { echo "$(RED)✗ ssh not found. Please install OpenSSH.$(NC)" >&2; exit 1; }
	@echo "$(GREEN)✓ SSH installed$(NC)"
	@# Check jq (optional)
	@command -v jq >/dev/null 2>&1 && echo "$(GREEN)✓ jq installed$(NC)" || echo "$(YELLOW)⚠ jq not found (optional). Install: brew install jq$(NC)"
	@# Check SSH deploy key for ArgoCD
	@if [ ! -f "$$HOME/.ssh/argocd-deploy-key" ]; then \
		echo "$(RED)✗ SSH deploy key not found at ~/.ssh/argocd-deploy-key$(NC)"; \
		echo "$(YELLOW)  Generate with: ssh-keygen -t ed25519 -C \"argocd-fineract-gitops\" -f ~/.ssh/argocd-deploy-key -N \"\"$(NC)"; \
		echo "$(YELLOW)  Then add public key to GitHub repository deploy keys$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ SSH deploy key found at ~/.ssh/argocd-deploy-key$(NC)"; \
	fi
	@# Check KUBECONFIG environment variable
	@if [ -z "$$KUBECONFIG" ]; then \
		echo "$(YELLOW)⚠ KUBECONFIG environment variable not set (using default ~/.kube/config)$(NC)"; \
	else \
		echo "$(GREEN)✓ KUBECONFIG environment variable is set: $$KUBECONFIG$(NC)"; \
		if [ -f "$$KUBECONFIG" ]; then \
			echo "$(GREEN)  ✓ KUBECONFIG file exists$(NC)"; \
		else \
			echo "$(RED)  ✗ KUBECONFIG file does not exist: $$KUBECONFIG$(NC)"; \
			exit 1; \
		fi; \
	fi
	@echo ""
	@echo "$(GREEN)✓ All Kubernetes/GitOps prerequisites validated$(NC)"

# Validate Ingress DNS matches LoadBalancer
validate-ingress-dns: ## Validate Ingress DNS matches LoadBalancer DNS
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE) Validating Ingress DNS Configuration$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)Environment:$(NC) $(ENV)"
	@./scripts/validate-ingress-dns.sh $(ENV)

# Kept for backwards compatibility - validates Terraform only
validate-terraform:
	@$(MAKE) validate-terraform-prereqs

# Setup Terraform backend (S3 + DynamoDB)
setup-terraform-backend:
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE) Setup Terraform Backend               $(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)This will create:$(NC)"
	@echo "  • S3 bucket for Terraform state storage"
	@echo "  • DynamoDB table for state locking"
	@echo ""
	@if [ -f scripts/setup-terraform-backend.sh ]; then \
		./scripts/setup-terraform-backend.sh; \
	elif [ -f terraform/aws/scripts/setup-terraform-backend.sh ]; then \
		cd terraform/aws && ./scripts/setup-terraform-backend.sh; \
	else \
		echo "$(YELLOW)Note: setup-terraform-backend.sh script not found$(NC)"; \
		echo "$(YELLOW)You can manually initialize the backend by following these steps:$(NC)"; \
		echo ""; \
		echo "1. Create an S3 bucket for state:"; \
		echo "   aws s3 mb s3://fineract-terraform-state-\$$(aws sts get-caller-identity --query Account --output text)"; \
		echo ""; \
		echo "2. Enable versioning:"; \
		echo "   aws s3api put-bucket-versioning --bucket fineract-terraform-state-\$$(aws sts get-caller-identity --query Account --output text) --versioning-configuration Status=Enabled"; \
		echo ""; \
		echo "3. Create DynamoDB table for locking:"; \
		echo "   aws dynamodb create-table --table-name terraform-state-lock --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST"; \
		echo ""; \
		echo "4. Create backend config files in terraform/aws/:"; \
		echo "   backend-dev.tfbackend, backend-uat.tfbackend, backend-production.tfbackend"; \
	fi

# Terraform init for each environment
terraform-init-dev:
	@echo "$(GREEN)Initializing Terraform for dev environment...$(NC)"
	@cd terraform/aws && terraform init -backend-config=backend-dev.tfbackend -reconfigure
	@echo "$(GREEN)✓ Terraform initialized for dev$(NC)"

terraform-init-uat:
	@echo "$(GREEN)Initializing Terraform for uat environment...$(NC)"
	@cd terraform/aws && terraform init -backend-config=backend-uat.tfbackend -reconfigure
	@echo "$(GREEN)✓ Terraform initialized for uat$(NC)"

terraform-init-prod:
	@echo "$(GREEN)Initializing Terraform for production environment...$(NC)"
	@cd terraform/aws && terraform init -backend-config=backend-production.tfbackend -reconfigure
	@echo "$(GREEN)✓ Terraform initialized for production$(NC)"

# Terraform plan for each environment
terraform-plan-dev:
	@echo "$(BLUE)Planning Terraform changes for dev...$(NC)"
	@cd terraform/aws && terraform plan -var-file=environments/dev-eks.tfvars -out=tfplan-dev
	@echo ""
	@echo "$(GREEN)✓ Plan saved to terraform/aws/tfplan-dev$(NC)"
	@echo "$(YELLOW)Review the plan above, then run: make terraform-apply-dev$(NC)"

terraform-plan-uat:
	@echo "$(BLUE)Planning Terraform changes for uat...$(NC)"
	@cd terraform/aws && terraform plan -var-file=environments/uat.tfvars -out=tfplan-uat
	@echo ""
	@echo "$(GREEN)✓ Plan saved to terraform/aws/tfplan-uat$(NC)"
	@echo "$(YELLOW)Review the plan above, then run: make terraform-apply-uat$(NC)"

terraform-plan-prod:
	@echo "$(BLUE)Planning Terraform changes for production...$(NC)"
	@cd terraform/aws && terraform plan -var-file=environments/production.tfvars -out=tfplan-prod
	@echo ""
	@echo "$(GREEN)✓ Plan saved to terraform/aws/tfplan-prod$(NC)"
	@echo "$(YELLOW)Review the plan above, then run: make terraform-apply-prod$(NC)"

# Terraform apply for each environment
terraform-apply-dev:
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Apply Terraform Changes - DEV         $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@if [ ! -f terraform/aws/tfplan-dev ]; then \
		echo "$(RED)✗ No plan file found. Run 'make terraform-plan-dev' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)This will apply infrastructure changes to dev environment$(NC)"
	@echo ""
	@cd terraform/aws && terraform apply tfplan-dev
	@rm -f terraform/aws/tfplan-dev
	@echo ""
	@echo "$(GREEN)✓ Terraform applied successfully for dev$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Generate sealed secrets: make seal-terraform-secrets ENV=dev"
	@echo "  2. Continue deployment: make deploy-step-3"

terraform-apply-uat:
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN) Apply Terraform Changes - UAT         $(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@if [ ! -f terraform/aws/tfplan-uat ]; then \
		echo "$(RED)✗ No plan file found. Run 'make terraform-plan-uat' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)This will apply infrastructure changes to uat environment$(NC)"
	@echo ""
	@read -p "Continue with apply? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "$(RED)Apply cancelled$(NC)"; \
		exit 1; \
	fi
	@cd terraform/aws && terraform apply tfplan-uat
	@rm -f terraform/aws/tfplan-uat
	@echo ""
	@echo "$(GREEN)✓ Terraform applied successfully for uat$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Generate sealed secrets: make seal-terraform-secrets ENV=uat"
	@echo "  2. Continue deployment: make deploy-step-3"

terraform-apply-prod:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) Apply Terraform Changes - PRODUCTION  $(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@if [ ! -f terraform/aws/tfplan-prod ]; then \
		echo "$(RED)✗ No plan file found. Run 'make terraform-plan-prod' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(RED)⚠ WARNING: This will apply changes to PRODUCTION!$(NC)"
	@echo ""
	@read -p "Type 'APPLY_PROD' to confirm: " confirm; \
	if [ "$$confirm" != "APPLY_PROD" ]; then \
		echo "$(RED)Apply cancelled$(NC)"; \
		exit 1; \
	fi
	@cd terraform/aws && terraform apply tfplan-prod
	@rm -f terraform/aws/tfplan-prod
	@echo ""
	@echo "$(GREEN)✓ Terraform applied successfully for production$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Generate sealed secrets: make seal-terraform-secrets ENV=prod"
	@echo "  2. Continue deployment: make deploy-step-3"

# Terraform destroy for each environment
terraform-destroy-dev:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) Destroy Infrastructure - DEV           $(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@echo "$(RED)⚠ WARNING: This will DESTROY all dev infrastructure!$(NC)"
	@echo ""
	@read -p "Type 'DESTROY_DEV' to confirm: " confirm; \
	if [ "$$confirm" != "DESTROY_DEV" ]; then \
		echo "$(RED)Destroy cancelled$(NC)"; \
		exit 1; \
	fi
	@cd terraform/aws && terraform destroy -var-file=environments/dev-eks.tfvars
	@echo "$(GREEN)✓ Infrastructure destroyed$(NC)"

terraform-destroy-uat:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) Destroy Infrastructure - UAT           $(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@echo "$(RED)⚠ WARNING: This will DESTROY all uat infrastructure!$(NC)"
	@echo ""
	@read -p "Type 'DESTROY_UAT' to confirm: " confirm; \
	if [ "$$confirm" != "DESTROY_UAT" ]; then \
		echo "$(RED)Destroy cancelled$(NC)"; \
		exit 1; \
	fi
	@cd terraform/aws && terraform destroy -var-file=environments/uat.tfvars
	@echo "$(GREEN)✓ Infrastructure destroyed$(NC)"

terraform-destroy-prod:
	@echo "$(RED)========================================$(NC)"
	@echo "$(RED) Destroy Infrastructure - PRODUCTION    $(NC)"
	@echo "$(RED)========================================$(NC)"
	@echo ""
	@echo "$(RED)⚠ DANGER: This will DESTROY PRODUCTION infrastructure!$(NC)"
	@echo ""
	@read -p "Type 'DESTROY_PRODUCTION' to confirm: " confirm; \
	if [ "$$confirm" != "DESTROY_PRODUCTION" ]; then \
		echo "$(RED)Destroy cancelled$(NC)"; \
		exit 1; \
	fi
	@cd terraform/aws && terraform destroy -var-file=environments/production.tfvars
	@echo "$(GREEN)✓ Infrastructure destroyed$(NC)"

# Terraform output for each environment
terraform-output-dev:
	@echo "$(BLUE)Terraform Outputs - DEV$(NC)"
	@echo ""
	@cd terraform/aws && terraform output

terraform-output-uat:
	@echo "$(BLUE)Terraform Outputs - UAT$(NC)"
	@echo ""
	@cd terraform/aws && terraform output

terraform-output-prod:
	@echo "$(BLUE)Terraform Outputs - PRODUCTION$(NC)"
	@echo ""
	@cd terraform/aws && terraform output

# Show deployment info
info:
	@echo "$(BLUE)Fineract GitOps - Deployment Information$(NC)"
	@echo ""
	@echo "$(GREEN)Repository:$(NC) $$(git remote get-url origin 2>/dev/null || echo 'Not in a git repository')"
	@echo "$(GREEN)Branch:$(NC) $$(git branch --show-current 2>/dev/null || echo 'Unknown')"
	@echo "$(GREEN)Last Commit:$(NC) $$(git log -1 --oneline 2>/dev/null || echo 'Unknown')"
	@echo ""
	@echo "$(GREEN)Terraform Version:$(NC) $$(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)"
	@echo "$(GREEN)kubectl Version:$(NC) $$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4)"
	@echo "$(GREEN)AWS CLI Version:$(NC) $$(aws --version | cut -d' ' -f1)"
	@echo ""

# GitOps Interactive Deployment Targets
deploy-gitops: ## Interactive full deployment with user confirmation
	@./scripts/deploy-gitops.sh

deploy-step-1: ## Step 1: Validate prerequisites
	@./scripts/steps/01-validate-prerequisites.sh

deploy-step-2: ## Step 2: Deploy core infrastructure
	@./scripts/steps/02-deploy-infrastructure.sh

deploy-step-3: ## Step 3: Setup ArgoCD and secrets
	@./scripts/steps/03-setup-argocd.sh

deploy-step-4: ## Step 4: Deploy app-of-apps
	@./scripts/steps/04-deploy-apps.sh

deploy-step-5: ## Step 5: Verify deployment
	@./scripts/steps/05-verify-deployment.sh

verify-namespaces: ## Verify all resources in correct namespaces
	@echo "$(BLUE)Verifying resource namespaces...$(NC)"
	@REDIS_NS=$$(kubectl get statefulset -A 2>/dev/null | grep fineract-redis | awk '{print $$1}' || echo "not-found"); \
	if [ "$$REDIS_NS" != "fineract-dev" ]; then \
	  echo "$(RED)✗ FAIL: Redis in wrong namespace: $$REDIS_NS (expected: fineract-dev)$(NC)"; \
	  exit 1; \
	fi; \
	echo "$(GREEN)✓ Redis in correct namespace: fineract-dev$(NC)"; \
	kubectl get all -n fineract-dev | grep -q "fineract-write" && echo "$(GREEN)✓ Fineract components in fineract-dev$(NC)" || (echo "$(RED)✗ Fineract components not found in fineract-dev$(NC)"; exit 1)

.DEFAULT_GOAL := help
