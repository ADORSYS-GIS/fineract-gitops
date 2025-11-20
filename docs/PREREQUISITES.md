# Prerequisites

Complete guide to installing and configuring all required tools for fineract-gitops deployment.

> 📋 **Version Information:** See [VERSION_MATRIX.md](VERSION_MATRIX.md) for specific version requirements.

---

## Quick Checklist

Before deploying fineract-gitops, ensure you have:

- [ ] **kubectl** (1.28+) - Kubernetes command-line tool
- [ ] **kustomize** (5.0+) - Kubernetes configuration management
- [ ] **AWS CLI** (2.0+) - AWS management (for AWS deployments)
- [ ] **Terraform** (1.5+) - Infrastructure as Code
- [ ] **ArgoCD CLI** (2.8+) - GitOps operations
- [ ] **kubeseal** (0.27.0) - Sealed Secrets management
- [ ] **Helm** (3.12+) - Kubernetes package manager (optional)
- [ ] **Python** (3.8+) - Operational scripts
- [ ] **Git** (2.30+) - Version control
- [ ] **Access to Kubernetes cluster** - EKS, K3s, or other

---

## Operating System Requirements

### Supported Platforms
- **macOS:** 12.0+ (Monterey or later)
- **Linux:** Ubuntu 20.04+, RHEL 8+, Amazon Linux 2023
- **Windows:** WSL2 with Ubuntu 22.04 (recommended)

### Hardware Requirements
- **CPU:** 4+ cores recommended
- **RAM:** 8GB minimum, 16GB recommended
- **Disk:** 50GB free space
- **Network:** Stable internet connection for downloading images

---

## Core Tools Installation

### 1. kubectl (Kubernetes CLI)

**Purpose:** Interact with Kubernetes clusters

#### macOS (Homebrew)
```bash
brew install kubectl

# Verify installation
kubectl version --client
```

#### Linux
```bash
# Download latest 1.28.x
curl -LO "https://dl.k8s.io/release/v1.28.5/bin/linux/amd64/kubectl"

# Make executable and move to PATH
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify
kubectl version --client
```

#### Windows (WSL2)
```bash
# Use Linux instructions above in WSL2 terminal
curl -LO "https://dl.k8s.io/release/v1.28.5/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Configuration:**
```bash
# Set up kubeconfig (will be configured during cluster setup)
export KUBECONFIG=~/.kube/config

# Enable autocomplete (bash)
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# Enable autocomplete (zsh)
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
```

---

### 2. kustomize (Kubernetes Configuration Management)

**Purpose:** Template-free Kubernetes configuration customization

> ⚠️ **Important:** Install standalone kustomize, not kubectl's built-in version (older)

#### macOS (Homebrew)
```bash
brew install kustomize

# Verify version (must be 5.0+)
kustomize version
```

#### Linux
```bash
# Download and install latest
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash

# Move to PATH
sudo mv kustomize /usr/local/bin/

# Verify
kustomize version
```

#### Verify Installation
```bash
# Should show 5.0+ (not 4.x from kubectl)
kustomize version | grep Version

# Test kustomize build
cd /path/to/fineract-gitops
kustomize build kubernetes/base
```

---

### 3. AWS CLI (AWS Management)

**Purpose:** Manage AWS resources and authenticate to EKS

#### macOS (Homebrew)
```bash
brew install awscli

# Verify
aws --version
```

#### Linux
```bash
# Download installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip

# Install
sudo ./aws/install

# Verify
aws --version
```

**Configuration:**
```bash
# Configure AWS credentials
aws configure

# Enter your credentials:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: eu-central-1 (or your preferred region)
# Default output format: json

# Verify configuration
aws sts get-caller-identity

# Output should show your account ID and user
```

**Alternative: AWS SSO**
```bash
# For organizations using AWS SSO
aws configure sso

# Follow prompts to authenticate via browser
# This creates profiles you can use with --profile flag
```

---

### 4. Terraform (Infrastructure as Code)

**Purpose:** Provision cloud infrastructure (EKS, RDS, VPC)

#### macOS (Homebrew)
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
```

#### Linux (Ubuntu/Debian)
```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install
sudo apt update && sudo apt install terraform

# Verify
terraform version
```

#### Linux (RHEL/Fedora)
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install terraform
```

---

### 5. ArgoCD CLI (GitOps Operations)

**Purpose:** Manage ArgoCD applications and sync operations

#### macOS (Homebrew)
```bash
brew install argocd

# Verify
argocd version --client
```

#### Linux
```bash
# Download latest
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

# Make executable and move to PATH
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Verify
argocd version --client
```

**Configuration:**
```bash
# Login to ArgoCD (after deployment)
argocd login <ARGOCD_SERVER> --username admin --password <ADMIN_PASSWORD>

# Or use port-forward for local access
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd login localhost:8080 --username admin --insecure
```

---

### 6. kubeseal (Sealed Secrets Management)

**Purpose:** Encrypt secrets for safe storage in Git

> ⚠️ **Critical:** kubeseal CLI version must match controller version (0.27.0)

#### macOS (Homebrew)
```bash
brew install kubeseal

# Verify version (must be 0.27.0)
kubeseal --version
```

#### Linux
```bash
# Download specific version (0.27.0)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz

# Extract and install
tar -xvzf kubeseal-0.27.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/

# Verify
kubeseal --version
```

**Configuration:**
```bash
# Fetch public key from cluster (after controller installation)
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > pub-cert.pem

# Encrypt a secret
kubectl create secret generic my-secret --dry-run=client --from-literal=password=mypassword -o yaml | \
  kubeseal --cert=pub-cert.pem --format=yaml > mysealedsecret.yaml
```

---

### 7. Helm (Kubernetes Package Manager)

**Purpose:** Install charts (optional, mainly for monitoring stack)

#### macOS (Homebrew)
```bash
brew install helm

# Verify
helm version
```

#### Linux
```bash
# Download install script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

**Configuration:**
```bash
# Add common repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami

# Update repositories
helm repo update
```

---

## Optional Tools

### eksctl (EKS Cluster Management)

**Purpose:** Simplified EKS cluster creation and management

#### macOS (Homebrew)
```bash
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Verify
eksctl version
```

#### Linux
```bash
# Download and install
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version
```

---

### gh (GitHub CLI)

**Purpose:** GitHub operations from command line

#### macOS (Homebrew)
```bash
brew install gh

# Authenticate
gh auth login
```

#### Linux
```bash
# Ubuntu/Debian
sudo apt install gh

# Authenticate
gh auth login
```

---

### jq (JSON Processor)

**Purpose:** Parse and manipulate JSON output

#### macOS (Homebrew)
```bash
brew install jq
```

#### Linux
```bash
sudo apt install jq  # Ubuntu/Debian
sudo dnf install jq  # RHEL/Fedora
```

---

### yq (YAML Processor)

**Purpose:** Parse and manipulate YAML files

#### macOS (Homebrew)
```bash
brew install yq
```

#### Linux
```bash
# Download latest
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

---

## Python Environment Setup

### Python 3.8+ Installation

#### macOS
```bash
# Python 3 is pre-installed on macOS 12+
python3 --version

# Or install latest via Homebrew
brew install python@3.11
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install python3 python3-pip python3-venv
```

### Install Operational Script Dependencies

```bash
# Navigate to operations directory
cd operations

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Verify installation
python -c "import yaml, requests, openpyxl; print('All dependencies installed')"
```

**Required Python Packages:**
- `pyyaml` - YAML parsing
- `requests` - HTTP requests to Fineract API
- `openpyxl` - Excel file handling (for data migration)

---

## Access Requirements

### AWS Account Access

Required permissions for AWS deployment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "rds:*",
        "s3:*",
        "iam:*",
        "cloudformation:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Security Note:** Use least-privilege policies in production. See [AWS_IAM_SETUP_GUIDE.md](AWS_IAM_SETUP_GUIDE.md).

### Kubernetes Cluster Access

You need one of:

1. **EKS Cluster:** AWS account with EKS permissions
2. **K3s Cluster:** EC2 instance or on-premises server
3. **Development Cluster:** minikube, kind, or Docker Desktop

**Verify cluster access:**
```bash
# Should list cluster nodes
kubectl get nodes

# Should show available contexts
kubectl config get-contexts

# Switch context if needed
kubectl config use-context <context-name>
```

---

## Git Configuration

### Basic Git Setup

```bash
# Configure identity
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Configure credential caching
git config --global credential.helper cache

# Set default branch name
git config --global init.defaultBranch main
```

### SSH Key Setup (for GitHub)

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Start SSH agent
eval "$(ssh-agent -s)"

# Add key to agent
ssh-add ~/.ssh/id_ed25519

# Copy public key
cat ~/.ssh/id_ed25519.pub
# Add this key to GitHub: Settings > SSH and GPG keys

# Test connection
ssh -T git@github.com
```

---

## Verification Script

Run this script to verify all prerequisites:

```bash
#!/bin/bash
# verify-prerequisites.sh

echo "Checking prerequisites for fineract-gitops..."
echo

# Function to check command
check_command() {
  if command -v $1 &> /dev/null; then
    version=$($2)
    echo "✅ $1: $version"
  else
    echo "❌ $1: NOT INSTALLED"
  fi
}

# Check core tools
check_command "kubectl" "kubectl version --client --short 2>/dev/null"
check_command "kustomize" "kustomize version --short 2>/dev/null"
check_command "aws" "aws --version 2>/dev/null"
check_command "terraform" "terraform version | head -1"
check_command "argocd" "argocd version --client --short 2>/dev/null"
check_command "kubeseal" "kubeseal --version 2>/dev/null"
check_command "helm" "helm version --short 2>/dev/null"

echo
echo "Optional tools:"
check_command "eksctl" "eksctl version 2>/dev/null"
check_command "gh" "gh --version | head -1"
check_command "jq" "jq --version"
check_command "yq" "yq --version"

echo
echo "Python environment:"
check_command "python3" "python3 --version"
check_command "pip3" "pip3 --version"

echo
echo "Cluster access:"
if kubectl get nodes &> /dev/null; then
  echo "✅ Kubernetes cluster: ACCESSIBLE"
  kubectl get nodes -o wide
else
  echo "❌ Kubernetes cluster: NOT ACCESSIBLE"
fi

echo
echo "AWS credentials:"
if aws sts get-caller-identity &> /dev/null; then
  echo "✅ AWS CLI: CONFIGURED"
  aws sts get-caller-identity
else
  echo "❌ AWS CLI: NOT CONFIGURED"
fi

echo
echo "Prerequisite check complete!"
```

**Save and run:**
```bash
chmod +x verify-prerequisites.sh
./verify-prerequisites.sh
```

---

## Troubleshooting

### kubectl: command not found
```bash
# Ensure /usr/local/bin is in PATH
echo $PATH | grep -q "/usr/local/bin" || export PATH="/usr/local/bin:$PATH"

# Add to shell profile
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### kustomize version is 4.x (too old)
```bash
# Remove kubectl's built-in kustomize from path
which kustomize  # Check which version is being used

# Reinstall standalone version
brew reinstall kustomize  # macOS
```

### AWS CLI not configured
```bash
# Check for credentials file
cat ~/.aws/credentials

# If missing, run configure
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="eu-central-1"
```

### kubeseal version mismatch
```bash
# Check controller version in cluster
kubectl get deployment -n kube-system sealed-secrets-controller -o jsonpath='{.spec.template.spec.containers[0].image}'

# Install matching CLI version
# If controller is 0.27.0, install kubeseal 0.27.0 (see installation above)
```

### Python dependencies fail to install
```bash
# Update pip first
pip3 install --upgrade pip

# Install with user flag if permission denied
pip3 install --user -r requirements.txt

# Or use virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## Next Steps

Once all prerequisites are installed:

1. **Clone Repository:**
   ```bash
   git clone https://github.com/adorsys-gis/fineract-gitops.git
   cd fineract-gitops
   ```

2. **Choose Deployment Path:**
   - **Quick Start:** [guides/QUICKSTART-AWS.md](guides/QUICKSTART-AWS.md)
   - **Interactive:** [DEPLOYMENT.md](../DEPLOYMENT.md)
   - **K3s (Cost-Optimized):** [guides/QUICKSTART-AWS-K3S.md](guides/QUICKSTART-AWS-K3S.md)

3. **Review Architecture:**
   - [ARCHITECTURE.md](ARCHITECTURE.md) - System design
   - [VERSION_MATRIX.md](VERSION_MATRIX.md) - Version compatibility

---

## Related Documentation

- [VERSION_MATRIX.md](VERSION_MATRIX.md) - Authoritative version requirements
- [GETTING_STARTED.md](GETTING_STARTED.md) - Beginner's guide
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Common commands cheat sheet
- [AWS_IAM_SETUP_GUIDE.md](AWS_IAM_SETUP_GUIDE.md) - Detailed AWS permissions
- [SECRETS_MANAGEMENT.md](SECRETS_MANAGEMENT.md) - Sealed Secrets deep dive

---

**Questions?**
- Check [docs/INDEX.md](INDEX.md) for complete documentation index
- Review [troubleshooting section](../DEPLOYMENT.md#troubleshooting) in deployment guide
- Open an issue on GitHub if you encounter problems
