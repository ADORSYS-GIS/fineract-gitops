#!/bin/bash
#
# Automated Terraform Destroy Script
# Safely destroys all AWS resources created by Terraform
#
# Usage: ./scripts/destroy-all.sh [environment]
# Example: ./scripts/destroy-all.sh dev
#
# ⚠️ WARNING: This will DELETE ALL AWS resources and is IRREVERSIBLE!
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

# Retry a command with exponential backoff
# Usage: retry_with_backoff "command" "description"
retry_with_backoff() {
    local command="$1"
    local description="$2"
    local max_attempts=3
    local attempt=1
    local wait_time=2

    while [ $attempt -le $max_attempts ]; do
        echo -e "${BLUE}  Attempt $attempt/$max_attempts: $description${NC}"
        if eval "$command"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo -e "${YELLOW}  Failed, waiting ${wait_time}s before retry...${NC}"
            sleep $wait_time
            wait_time=$((wait_time * 2))  # Exponential backoff: 2s, 4s, 8s
        fi
        attempt=$((attempt + 1))
    done

    echo -e "${RED}  Failed after $max_attempts attempts${NC}"
    return 1
}

# Wait for a resource to be deleted (poll AWS API)
# Usage: wait_for_resource_deletion "check_command" "resource_name" max_seconds
wait_for_resource_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_seconds="${3:-300}"  # Default 5 minutes
    local elapsed=0

    echo -e "${BLUE}  Waiting for $resource_name deletion...${NC}"

    while [ $elapsed -lt $max_seconds ]; do
        if ! eval "$check_command" &>/dev/null; then
            echo -e "${GREEN}  ✓ $resource_name deleted (${elapsed}s)${NC}"
            return 0
        fi

        if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo -e "${BLUE}    Still waiting... (${elapsed}s/${max_seconds}s)${NC}"
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo -e "${YELLOW}  ⚠ Timeout waiting for $resource_name deletion after ${max_seconds}s${NC}"
    return 1
}

# Cleanup all ENIs in a VPC
# Usage: cleanup_all_enis_in_vpc "vpc-id" "region"
cleanup_all_enis_in_vpc() {
    local vpc_id="$1"
    local region="$2"

    echo -e "${BLUE}  Finding all Network Interfaces in VPC...${NC}"

    # Get all available ENIs
    local available_enis=$(aws ec2 describe-network-interfaces \
        --region "$region" \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=available" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")

    # Get all in-use ENIs that are ELB or Kubernetes-related
    local inuse_enis=$(aws ec2 describe-network-interfaces \
        --region "$region" \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=status,Values=in-use" \
        --query "NetworkInterfaces[?contains(Description, 'ELB') || contains(Description, 'aws-k8s') || contains(Description, 'EKS')].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")

    local all_enis="$available_enis $inuse_enis"

    if [ -n "$all_enis" ] && [ "$all_enis" != " " ]; then
        for eni_id in $all_enis; do
            echo -e "${BLUE}    Deleting ENI: $eni_id${NC}"
            retry_with_backoff \
                "aws ec2 delete-network-interface --region $region --network-interface-id $eni_id 2>/dev/null" \
                "Delete ENI $eni_id" || true
        done
        echo -e "${GREEN}  ✓ Network Interfaces cleaned up${NC}"
        sleep 10  # Wait for ENI deletion to propagate
    else
        echo -e "${GREEN}  ✓ No Network Interfaces to clean up${NC}"
    fi
}

# Cleanup Security Groups with dependency resolution
# Usage: cleanup_security_groups_with_retry "vpc-id" "region"
cleanup_security_groups_with_retry() {
    local vpc_id="$1"
    local region="$2"

    echo -e "${BLUE}  Cleaning up Security Groups...${NC}"

    # Get all non-default security groups
    local sg_ids=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || echo "")

    if [ -z "$sg_ids" ]; then
        echo -e "${GREEN}  ✓ No Security Groups to clean up${NC}"
        return 0
    fi

    # Step 1: Remove all rules from all security groups (break dependencies)
    echo -e "${BLUE}    Removing all Security Group rules...${NC}"
    for sg_id in $sg_ids; do
        # Revoke all ingress rules
        aws ec2 describe-security-groups --region "$region" --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null | \
            jq -c '.[]' 2>/dev/null | while read rule; do
                aws ec2 revoke-security-group-ingress --region "$region" \
                    --group-id "$sg_id" --ip-permissions "$rule" 2>/dev/null || true
            done

        # Revoke all egress rules
        aws ec2 describe-security-groups --region "$region" --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissionsEgress" --output json 2>/dev/null | \
            jq -c '.[]' 2>/dev/null | while read rule; do
                aws ec2 revoke-security-group-egress --region "$region" \
                    --group-id "$sg_id" --ip-permissions "$rule" 2>/dev/null || true
            done
    done

    sleep 5  # Wait for rule removal to propagate

    # Step 2: Delete security groups with retry
    echo -e "${BLUE}    Deleting Security Groups...${NC}"
    for sg_id in $sg_ids; do
        retry_with_backoff \
            "aws ec2 delete-security-group --region $region --group-id $sg_id 2>/dev/null" \
            "Delete SG $sg_id" || true
    done

    echo -e "${GREEN}  ✓ Security Groups cleaned up${NC}"
}

# Cleanup EKS-specific resources
# Usage: cleanup_eks_resources "cluster-name" "region"
cleanup_eks_resources() {
    local cluster_name="$1"
    local region="$2"

    # Check if cluster exists
    if ! aws eks describe-cluster --region "$region" --name "$cluster_name" &>/dev/null; then
        echo -e "${GREEN}  ✓ EKS cluster already deleted${NC}"
        return 0
    fi

    echo -e "${BLUE}  Cleaning up EKS-specific resources...${NC}"

    # Delete EKS add-ons
    local addons="vpc-cni kube-proxy coredns aws-ebs-csi-driver amazon-cloudwatch-observability"
    for addon in $addons; do
        if aws eks describe-addon --region "$region" --cluster-name "$cluster_name" --addon-name "$addon" &>/dev/null; then
            echo -e "${BLUE}    Deleting EKS add-on: $addon${NC}"
            aws eks delete-addon --region "$region" --cluster-name "$cluster_name" --addon-name "$addon" 2>/dev/null || true
        fi
    done

    # Wait for add-ons to delete
    sleep 30

    # Node groups will be deleted by Terraform, but verify they're terminating
    local node_groups=$(aws eks list-nodegroups --region "$region" --cluster-name "$cluster_name" \
        --query "nodegroups[]" --output text 2>/dev/null || echo "")

    if [ -n "$node_groups" ]; then
        echo -e "${BLUE}    Waiting for node groups to terminate...${NC}"
        for ng in $node_groups; do
            echo -e "${BLUE}      Node group: $ng${NC}"
        done
        # Terraform will handle deletion, we just verify status
    fi

    echo -e "${GREEN}  ✓ EKS resources cleanup initiated${NC}"
}

# Scan for orphaned resources
# Usage: scan_for_orphaned_resources "environment" "region"
scan_for_orphaned_resources() {
    local env="$1"
    local region="$2"

    echo -e "${BLUE}  Scanning for orphaned resources (Project=fineract, Environment=$env)...${NC}"

    # Find orphaned VPCs
    local orphaned_vpcs=$(aws ec2 describe-vpcs --region "$region" \
        --filters "Name=tag:Project,Values=fineract" "Name=tag:Environment,Values=$env" \
        --query "Vpcs[].VpcId" --output text 2>/dev/null || echo "")

    if [ -n "$orphaned_vpcs" ]; then
        echo -e "${YELLOW}  Found orphaned VPCs: $orphaned_vpcs${NC}"

        for vpc_id in $orphaned_vpcs; do
            echo -e "${YELLOW}    Cleaning up orphaned VPC: $vpc_id${NC}"

            # Cleanup ENIs in orphaned VPC
            cleanup_all_enis_in_vpc "$vpc_id" "$region"

            # Cleanup LoadBalancers in orphaned VPC
            cleanup_loadbalancers_in_vpc "$vpc_id" "$region"

            # Cleanup NAT Gateways
            local nat_gws=$(aws ec2 describe-nat-gateways --region "$region" \
                --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
                --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || echo "")

            if [ -n "$nat_gws" ]; then
                for nat_id in $nat_gws; do
                    echo -e "${BLUE}      Deleting NAT Gateway: $nat_id${NC}"
                    aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat_id" 2>/dev/null || true
                done
                echo -e "${BLUE}      Waiting 120s for NAT Gateway deletion...${NC}"
                sleep 120
            fi

            # Cleanup Internet Gateway
            local igw_id=$(aws ec2 describe-internet-gateways --region "$region" \
                --filters "Name=attachment.vpc-id,Values=$vpc_id" \
                --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "")

            if [ -n "$igw_id" ] && [ "$igw_id" != "None" ]; then
                echo -e "${BLUE}      Detaching and deleting Internet Gateway: $igw_id${NC}"
                aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" 2>/dev/null || true
                sleep 10
                aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw_id" 2>/dev/null || true
            fi

            # Cleanup Security Groups
            cleanup_security_groups_with_retry "$vpc_id" "$region"

            # Cleanup Subnets
            local subnets=$(aws ec2 describe-subnets --region "$region" \
                --filters "Name=vpc-id,Values=$vpc_id" \
                --query "Subnets[].SubnetId" --output text 2>/dev/null || echo "")

            if [ -n "$subnets" ]; then
                for subnet_id in $subnets; do
                    echo -e "${BLUE}      Deleting subnet: $subnet_id${NC}"
                    aws ec2 delete-subnet --region "$region" --subnet-id "$subnet_id" 2>/dev/null || true
                done
            fi

            # Delete VPC
            echo -e "${BLUE}      Deleting VPC: $vpc_id${NC}"
            retry_with_backoff \
                "aws ec2 delete-vpc --region $region --vpc-id $vpc_id" \
                "Delete VPC $vpc_id" || true
        done

        echo -e "${GREEN}  ✓ Orphaned resources cleaned up${NC}"
    else
        echo -e "${GREEN}  ✓ No orphaned VPCs found${NC}"
    fi
}

# Cleanup LoadBalancers in a VPC
# Usage: cleanup_loadbalancers_in_vpc "vpc-id" "region"
cleanup_loadbalancers_in_vpc() {
    local vpc_id="$1"
    local region="$2"

    local lb_arns=$(aws elbv2 describe-load-balancers --region "$region" \
        --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$lb_arns" ]; then
        echo -e "${BLUE}    Found LoadBalancers in VPC${NC}"
        for lb_arn in $lb_arns; do
            local lb_name=$(aws elbv2 describe-load-balancers --region "$region" \
                --load-balancer-arns "$lb_arn" \
                --query "LoadBalancers[0].LoadBalancerName" --output text)
            echo -e "${BLUE}      Deleting LoadBalancer: $lb_name${NC}"
            aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$lb_arn" 2>/dev/null || true
        done
        echo -e "${BLUE}    Waiting 120s for LoadBalancer deletion...${NC}"
        sleep 120
    fi

    # Cleanup Target Groups
    local tg_arns=$(aws elbv2 describe-target-groups --region "$region" \
        --query "TargetGroups[?VpcId=='${vpc_id}'].TargetGroupArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "$tg_arns" ]; then
        for tg_arn in $tg_arns; do
            echo -e "${BLUE}      Deleting Target Group: $tg_arn${NC}"
            aws elbv2 delete-target-group --region "$region" --target-group-arn "$tg_arn" 2>/dev/null || true
        done
    fi
}

# Cleanup CloudWatch Log Groups (Legacy Resources)
# CloudWatch is no longer deployed in new infrastructure, but this function
# cleans up log groups from previous deployments when CloudWatch was enabled.
# This prevents accumulation of log data and associated storage costs.
# Usage: cleanup_cloudwatch_logs "cluster-name" "region"
cleanup_cloudwatch_logs() {
    local cluster_name="$1"
    local region="$2"

    echo -e "${BLUE}  Cleaning up CloudWatch Log Groups...${NC}"

    local log_group_prefix="/aws/eks/$cluster_name"
    local log_groups=$(aws logs describe-log-groups --region "$region" \
        --log-group-name-prefix "$log_group_prefix" \
        --query "logGroups[].logGroupName" --output text 2>/dev/null || echo "")

    if [ -n "$log_groups" ]; then
        for log_group in $log_groups; do
            echo -e "${BLUE}    Deleting log group: $log_group${NC}"
            aws logs delete-log-group --region "$region" --log-group-name "$log_group" 2>/dev/null || true
        done
        echo -e "${GREEN}  ✓ CloudWatch Log Groups deleted${NC}"
    else
        echo -e "${GREEN}  ✓ No CloudWatch Log Groups to clean up${NC}"
    fi
}

#==============================================================================
# MAIN SCRIPT
#==============================================================================

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment argument required${NC}"
    echo "Usage: $0 [dev|uat|production]"
    exit 1
fi

ENV=$1

# Validate environment
if [[ ! "$ENV" =~ ^(dev|uat|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be dev, uat, or production${NC}"
    exit 1
fi

# Determine tfvars file (dev uses -eks suffix for EKS deployment)
if [ "$ENV" = "dev" ]; then
    TFVARS_FILE="environments/${ENV}-eks.tfvars"
else
    TFVARS_FILE="environments/${ENV}.tfvars"
fi

# Check if tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: Terraform variables file not found: $TFVARS_FILE${NC}"
    exit 1
fi

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║              ⚠️  TERRAFORM DESTROY WARNING  ⚠️                  ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  This will PERMANENTLY DELETE all AWS resources created by    ║${NC}"
echo -e "${RED}║  Terraform for the ${ENV} environment.                        ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  ALL DATA WILL BE LOST:                                        ║${NC}"
echo -e "${RED}║  - RDS databases (Fineract, Keycloak)                          ║${NC}"
echo -e "${RED}║  - S3 buckets and all stored files                             ║${NC}"
echo -e "${RED}║  - AWS Secrets Manager secrets                                 ║${NC}"
echo -e "${RED}║  - VPC, subnets, NAT gateway                                   ║${NC}"
echo -e "${RED}║  - IAM roles and policies                                      ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}║  This action is IRREVERSIBLE and cannot be undone!            ║${NC}"
echo -e "${RED}║                                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Estimate cost savings
case $ENV in
    dev)
        MONTHLY_COST="$110-140"
        YEARLY_COST="$1,320-1,680"
        ;;
    uat)
        MONTHLY_COST="$150-180"
        YEARLY_COST="$1,800-2,160"
        ;;
    production)
        MONTHLY_COST="$300-500"
        YEARLY_COST="$3,600-6,000"
        ;;
esac

echo -e "${BLUE}Cost Savings After Destruction:${NC}"
echo "  Monthly: ~${MONTHLY_COST}"
echo "  Yearly: ~${YEARLY_COST}"
echo

# Ask for confirmation
echo -e "${YELLOW}Are you absolutely sure you want to destroy all resources?${NC}"
echo "Type 'DESTROY-${ENV}' to confirm:"
read -r CONFIRMATION

if [ "$CONFIRMATION" != "DESTROY-${ENV}" ]; then
    echo -e "${GREEN}Destruction cancelled. No resources were deleted.${NC}"
    exit 0
fi

echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform not found${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: aws CLI not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
    echo
fi

# Step 1: Show destruction plan
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 1: Analyzing resources to be destroyed...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

terraform plan -destroy -var-file="$TFVARS_FILE" -out=destroy.tfplan

# Count resources
DESTROY_COUNT=$(terraform show -json destroy.tfplan | jq '.resource_changes | length')
echo
echo -e "${YELLOW}Resources to be destroyed: ${DESTROY_COUNT}${NC}"
echo

# Final confirmation
echo -e "${YELLOW}This is your last chance to cancel!${NC}"
echo "Press Ctrl+C now to abort, or press Enter to continue..."
read -r

# Step 2: Backup Terraform state
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2: Backing up Terraform state...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

BACKUP_DIR="../../backups/terraform-state-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "terraform.tfstate" ]; then
    cp terraform.tfstate "$BACKUP_DIR/terraform.tfstate.backup"
    echo -e "${GREEN}✓ State backed up to: $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}⚠ No local state file found (may be using remote backend)${NC}"
fi

echo

# Step 2.5: Pre-Terraform Comprehensive Cleanup
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2.5: Pre-Terraform Resource Cleanup...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Get VPC ID and region from Terraform state
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || \
         terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="aws_vpc") | .values.id' 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-2")
CLUSTER_NAME="fineract-${ENV}"

if [ -z "$VPC_ID" ]; then
  echo -e "${YELLOW}  Could not determine VPC ID from Terraform state${NC}"
  echo -e "${YELLOW}  Will rely on orphan scanning in Step 2.7${NC}"
else
  echo -e "${BLUE}  VPC ID: $VPC_ID${NC}"
  echo -e "${BLUE}  Region: $AWS_REGION${NC}"
  echo -e "${BLUE}  Cluster: $CLUSTER_NAME${NC}"
  echo

  # Step 2.5a: Try Kubernetes cleanup if cluster is accessible
  echo -e "${BLUE}→ Step 2.5a: Checking Kubernetes cluster access...${NC}"
  KUBECONFIG_FILE="${HOME}/.kube/config-fineract-${ENV}"
  if [ -f "$KUBECONFIG_FILE" ]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
    if kubectl cluster-info &>/dev/null; then
      echo -e "${YELLOW}  Kubernetes cluster is still accessible${NC}"
      echo -e "${YELLOW}  Recommend running: make cleanup-cluster ENV=$ENV${NC}"
      echo -e "${YELLOW}  Continuing with AWS cleanup...${NC}"
    else
      echo -e "${GREEN}  ✓ Kubernetes cluster not accessible${NC}"
    fi
  else
    echo -e "${GREEN}  ✓ No kubeconfig found${NC}"
  fi
  echo

  # Step 2.5b: Delete ALL LoadBalancers (ALB + NLB)
  echo -e "${BLUE}→ Step 2.5b: Cleaning up LoadBalancers...${NC}"
  cleanup_loadbalancers_in_vpc "$VPC_ID" "$AWS_REGION"
  echo

  # Step 2.5c: Cleanup Network Interfaces
  echo -e "${BLUE}→ Step 2.5c: Cleaning up Network Interfaces...${NC}"
  cleanup_all_enis_in_vpc "$VPC_ID" "$AWS_REGION"
  echo

  # Step 2.5d: Cleanup EKS-specific resources
  echo -e "${BLUE}→ Step 2.5d: Cleaning up EKS resources...${NC}"
  cleanup_eks_resources "$CLUSTER_NAME" "$AWS_REGION"
  echo

  # Step 2.5e: Cleanup Security Groups
  echo -e "${BLUE}→ Step 2.5e: Cleaning up Security Groups...${NC}"
  cleanup_security_groups_with_retry "$VPC_ID" "$AWS_REGION"
  echo

  # Step 2.5f: Cleanup NAT Gateways (must wait for full deletion)
  echo -e "${BLUE}→ Step 2.5f: Cleaning up NAT Gateways...${NC}"
  NAT_GWS=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || echo "")

  if [ -n "$NAT_GWS" ]; then
    for nat_id in $NAT_GWS; do
      echo -e "${BLUE}    Deleting NAT Gateway: $nat_id${NC}"
      aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id "$nat_id" 2>/dev/null || true
    done

    # Wait for NAT Gateways to fully delete (can take 5-10 minutes)
    echo -e "${BLUE}    Waiting for NAT Gateways to delete (up to 10 minutes)...${NC}"
    elapsed=0
    max_wait=600
    while [ $elapsed -lt $max_wait ]; do
      remaining=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,deleting,available" \
        --query "NatGateways | length(@)" --output text 2>/dev/null || echo "0")

      if [ "$remaining" = "0" ]; then
        echo -e "${GREEN}  ✓ All NAT Gateways deleted (${elapsed}s)${NC}"
        break
      fi

      if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -gt 0 ]; then
        echo -e "${BLUE}      Still waiting... ($remaining NAT gateways remaining, ${elapsed}s/${max_wait}s)${NC}"
      fi

      sleep 10
      elapsed=$((elapsed + 10))
    done

    if [ "$remaining" != "0" ]; then
      echo -e "${YELLOW}  ⚠ $remaining NAT Gateways still deleting after ${max_wait}s${NC}"
    fi
  else
    echo -e "${GREEN}  ✓ No NAT Gateways to clean up${NC}"
  fi
  echo

  # Step 2.5g: Release Elastic IPs (after NAT deletion)
  echo -e "${BLUE}→ Step 2.5g: Releasing Elastic IPs...${NC}"
  # Elastic IPs will be released automatically when NAT Gateways are deleted
  # But we can verify they're not associated
  EIP_ALLOCS=$(aws ec2 describe-addresses --region "$AWS_REGION" \
    --filters "Name=tag:Environment,Values=$ENV" "Name=tag:Project,Values=fineract" \
    --query "Addresses[?AssociationId==null].AllocationId" --output text 2>/dev/null || echo "")

  if [ -n "$EIP_ALLOCS" ]; then
    for eip_id in $EIP_ALLOCS; do
      echo -e "${BLUE}    Releasing Elastic IP: $eip_id${NC}"
      aws ec2 release-address --region "$AWS_REGION" --allocation-id "$eip_id" 2>/dev/null || true
    done
    echo -e "${GREEN}  ✓ Elastic IPs released${NC}"
  else
    echo -e "${GREEN}  ✓ No unassociated Elastic IPs to release${NC}"
  fi
  echo

  # Step 2.5h: Cleanup CloudWatch Log Groups
  echo -e "${BLUE}→ Step 2.5h: Cleaning up CloudWatch Logs...${NC}"
  cleanup_cloudwatch_logs "$CLUSTER_NAME" "$AWS_REGION"
  echo
fi

# Step 2.7: Scan for orphaned resources
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2.7: Scanning for Orphaned Resources...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

scan_for_orphaned_resources "$ENV" "$AWS_REGION"

echo

# Step 3: Empty S3 buckets
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3: Emptying S3 buckets...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Get S3 bucket names from Terraform output
DOCS_BUCKET=$(terraform output -raw documents_bucket_name 2>/dev/null || echo "")
BACKUPS_BUCKET=$(terraform output -raw backups_bucket_name 2>/dev/null || echo "")
ARTIFACTS_BUCKET=$(terraform output -raw artifacts_bucket_name 2>/dev/null || echo "")

empty_bucket() {
    local bucket=$1
    if [ -n "$bucket" ]; then
        echo "Emptying bucket: $bucket"
        if aws s3 ls "s3://$bucket" &>/dev/null; then
            # Delete all objects
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true

            # Delete all versions (if versioning is enabled)
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --output json \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
            jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            xargs -I {} aws s3api delete-object --bucket "$bucket" {} 2>/dev/null || true

            # Delete all delete markers
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --output json \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
            jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
            xargs -I {} aws s3api delete-object --bucket "$bucket" {} 2>/dev/null || true

            echo -e "${GREEN}✓ Bucket $bucket emptied${NC}"
        else
            echo -e "${YELLOW}⚠ Bucket $bucket not found or already deleted${NC}"
        fi
    fi
}

empty_bucket "$DOCS_BUCKET"
empty_bucket "$BACKUPS_BUCKET"
empty_bucket "$ARTIFACTS_BUCKET"

echo

# Step 4: Disable RDS deletion protection
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 4: Disabling RDS deletion protection...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

RDS_INSTANCE=$(terraform output -raw rds_instance_id 2>/dev/null || echo "")

if [ -n "$RDS_INSTANCE" ]; then
    echo "Checking RDS instance: $RDS_INSTANCE"

    # Check if deletion protection is enabled
    DELETION_PROTECTION=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE" \
        --query "DBInstances[0].DeletionProtection" \
        --output text 2>/dev/null || echo "")

    if [ "$DELETION_PROTECTION" = "True" ]; then
        echo "Disabling deletion protection..."
        aws rds modify-db-instance \
            --db-instance-identifier "$RDS_INSTANCE" \
            --no-deletion-protection \
            --apply-immediately

        echo "Waiting for modification to complete (30 seconds)..."
        sleep 30

        echo -e "${GREEN}✓ RDS deletion protection disabled${NC}"
    else
        echo -e "${GREEN}✓ RDS deletion protection already disabled${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No RDS instance found${NC}"
fi

echo

# Step 5: Execute destruction with retry
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 5: Destroying all resources...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Track start time
DESTROY_START_TIME=$(date +%s)

# Attempt Terraform destroy with retry logic
DESTROY_ATTEMPT=1
DESTROY_SUCCESS=false

while [ $DESTROY_ATTEMPT -le 3 ]; do
  echo -e "${BLUE}→ Destroy attempt $DESTROY_ATTEMPT/3${NC}"

  if terraform apply destroy.tfplan; then
    DESTROY_SUCCESS=true
    break
  else
    echo -e "${RED}✗ Terraform destroy failed on attempt $DESTROY_ATTEMPT${NC}"

    if [ $DESTROY_ATTEMPT -lt 3 ]; then
      echo -e "${YELLOW}→ Running enhanced cleanup before retry...${NC}"

      # Re-run comprehensive cleanup
      if [ -n "$VPC_ID" ]; then
        cleanup_loadbalancers_in_vpc "$VPC_ID" "$AWS_REGION"
        cleanup_all_enis_in_vpc "$VPC_ID" "$AWS_REGION"
        cleanup_security_groups_with_retry "$VPC_ID" "$AWS_REGION"
      fi

      # Scan for orphans again
      scan_for_orphaned_resources "$ENV" "$AWS_REGION"

      echo -e "${YELLOW}→ Regenerating destroy plan...${NC}"
      terraform plan -destroy -var-file="$TFVARS_FILE" -out=destroy.tfplan

      echo -e "${YELLOW}→ Waiting 30 seconds before retry...${NC}"
      sleep 30
    fi
  fi

  DESTROY_ATTEMPT=$((DESTROY_ATTEMPT + 1))
done

DESTROY_END_TIME=$(date +%s)
DESTROY_DURATION=$((DESTROY_END_TIME - DESTROY_START_TIME))

echo
if [ "$DESTROY_SUCCESS" = true ]; then
  echo -e "${GREEN}✓ Terraform destroy completed successfully (${DESTROY_DURATION}s)${NC}"
else
  echo -e "${RED}✗ Terraform destroy failed after 3 attempts${NC}"
  echo -e "${RED}  Manual intervention may be required${NC}"
  echo -e "${YELLOW}  Check terraform logs and AWS Console for remaining resources${NC}"
fi
echo

# Step 6: Comprehensive Verification with Polling
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 6: Comprehensive Verification...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Initialize verification trackers
VERIFICATION_FAILED=false
FAILED_RESOURCES=()

# Check 1: Terraform state
echo -e "${BLUE}→ Verifying Terraform state...${NC}"
REMAINING_RESOURCES=$(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")

if [ "$REMAINING_RESOURCES" = "0" ]; then
    echo -e "${GREEN}  ✓ Terraform state is empty (all resources destroyed)${NC}"
else
    echo -e "${YELLOW}  ⚠ Warning: $REMAINING_RESOURCES resources remain in state${NC}"
    VERIFICATION_FAILED=true
    FAILED_RESOURCES+=("Terraform state: $REMAINING_RESOURCES resources")
fi
echo

# Check 2: VPC deletion (with polling)
echo -e "${BLUE}→ Verifying VPC deletion...${NC}"
if [ -n "$VPC_ID" ]; then
    wait_for_resource_deletion \
        "aws ec2 describe-vpcs --region $AWS_REGION --vpc-ids $VPC_ID 2>/dev/null" \
        "VPC $VPC_ID" \
        180 || {
            VERIFICATION_FAILED=true
            FAILED_RESOURCES+=("VPC: $VPC_ID still exists")
        }
else
    echo -e "${GREEN}  ✓ No VPC to verify${NC}"
fi
echo

# Check 3: EKS Cluster deletion (with polling)
echo -e "${BLUE}→ Verifying EKS cluster deletion...${NC}"
wait_for_resource_deletion \
    "aws eks describe-cluster --region $AWS_REGION --name $CLUSTER_NAME 2>/dev/null" \
    "EKS cluster $CLUSTER_NAME" \
    120 || {
        # EKS might already be deleted, so this is okay
        echo -e "${GREEN}  ✓ EKS cluster deleted${NC}"
    }
echo

# Check 4: RDS instance
echo -e "${BLUE}→ Verifying RDS deletion...${NC}"
RDS_INSTANCE=$(terraform output -raw rds_instance_id 2>/dev/null || echo "")
if [ -n "$RDS_INSTANCE" ]; then
    RDS_STATUS=$(aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --db-instance-identifier "$RDS_INSTANCE" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text 2>/dev/null || echo "deleted")

    if [ "$RDS_STATUS" = "deleted" ] || [ "$RDS_STATUS" = "deleting" ]; then
        echo -e "${GREEN}  ✓ RDS instance deleted or deleting${NC}"
    else
        echo -e "${YELLOW}  ⚠ RDS instance still exists (status: $RDS_STATUS)${NC}"
        VERIFICATION_FAILED=true
        FAILED_RESOURCES+=("RDS: $RDS_INSTANCE (status: $RDS_STATUS)")
    fi
else
    echo -e "${GREEN}  ✓ No RDS instance to verify${NC}"
fi
echo

# Check 5: S3 buckets
echo -e "${BLUE}→ Verifying S3 bucket deletion...${NC}"
S3_BUCKETS=$(aws s3 ls 2>/dev/null | grep "fineract-${ENV}" || echo "")
if [ -z "$S3_BUCKETS" ]; then
    echo -e "${GREEN}  ✓ All S3 buckets deleted${NC}"
else
    echo -e "${YELLOW}  ⚠ Some S3 buckets still exist:${NC}"
    echo "$S3_BUCKETS" | while read bucket; do
        echo -e "${YELLOW}    - $bucket${NC}"
    done
    VERIFICATION_FAILED=true
    FAILED_RESOURCES+=("S3 buckets still exist")
fi
echo

# Check 6: LoadBalancers
echo -e "${BLUE}→ Verifying LoadBalancer deletion...${NC}"
if [ -n "$VPC_ID" ]; then
    LB_COUNT=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query "LoadBalancers[?VpcId=='${VPC_ID}'] | length(@)" \
        --output text 2>/dev/null || echo "0")

    if [ "$LB_COUNT" = "0" ]; then
        echo -e "${GREEN}  ✓ All LoadBalancers deleted${NC}"
    else
        echo -e "${YELLOW}  ⚠ $LB_COUNT LoadBalancer(s) still exist${NC}"
        VERIFICATION_FAILED=true
        FAILED_RESOURCES+=("LoadBalancers: $LB_COUNT remaining")
    fi
else
    echo -e "${GREEN}  ✓ No VPC to check for LoadBalancers${NC}"
fi
echo

# Check 7: NAT Gateways
echo -e "${BLUE}→ Verifying NAT Gateway deletion...${NC}"
if [ -n "$VPC_ID" ]; then
    NAT_COUNT=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending,deleting" \
        --query "NatGateways | length(@)" --output text 2>/dev/null || echo "0")

    if [ "$NAT_COUNT" = "0" ]; then
        echo -e "${GREEN}  ✓ All NAT Gateways deleted${NC}"
    else
        echo -e "${YELLOW}  ⚠ $NAT_COUNT NAT Gateway(s) still exist or deleting${NC}"
        # This is okay if they're in deleting state
    fi
else
    echo -e "${GREEN}  ✓ No VPC to check for NAT Gateways${NC}"
fi
echo

# Check 8: Security Groups
echo -e "${BLUE}→ Verifying Security Group deletion...${NC}"
if [ -n "$VPC_ID" ]; then
    SG_COUNT=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'] | length(@)" \
        --output text 2>/dev/null || echo "0")

    if [ "$SG_COUNT" = "0" ]; then
        echo -e "${GREEN}  ✓ All non-default Security Groups deleted${NC}"
    else
        echo -e "${YELLOW}  ⚠ $SG_COUNT non-default Security Group(s) still exist${NC}"
        VERIFICATION_FAILED=true
        FAILED_RESOURCES+=("Security Groups: $SG_COUNT remaining")
    fi
else
    echo -e "${GREEN}  ✓ No VPC to check for Security Groups${NC}"
fi
echo

# Check 9: ENIs
echo -e "${BLUE}→ Verifying Network Interface deletion...${NC}"
if [ -n "$VPC_ID" ]; then
    ENI_COUNT=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces | length(@)" --output text 2>/dev/null || echo "0")

    if [ "$ENI_COUNT" = "0" ]; then
        echo -e "${GREEN}  ✓ All Network Interfaces deleted${NC}"
    else
        echo -e "${YELLOW}  ⚠ $ENI_COUNT Network Interface(s) still exist${NC}"
        VERIFICATION_FAILED=true
        FAILED_RESOURCES+=("ENIs: $ENI_COUNT remaining")
    fi
else
    echo -e "${GREEN}  ✓ No VPC to check for ENIs${NC}"
fi
echo

# Check 10: CloudWatch Log Groups (Legacy Resources)
# Note: CloudWatch is no longer deployed, but we check for legacy log groups
# from previous deployments to ensure complete cleanup.
echo -e "${BLUE}→ Verifying CloudWatch Log Groups deletion...${NC}"
LOG_GROUP_COUNT=$(aws logs describe-log-groups --region "$AWS_REGION" \
    --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" \
    --query "logGroups | length(@)" --output text 2>/dev/null || echo "0")

if [ "$LOG_GROUP_COUNT" = "0" ]; then
    echo -e "${GREEN}  ✓ All CloudWatch Log Groups deleted${NC}"
else
    echo -e "${YELLOW}  ⚠ $LOG_GROUP_COUNT CloudWatch Log Group(s) still exist (legacy)${NC}"
    # This is informational, not critical
fi
echo

# Step 6.5: Final Aggressive Cleanup (if verification failed)
if [ "$VERIFICATION_FAILED" = true ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Step 6.5: Final Aggressive Cleanup...${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Verification found remaining resources. Running final cleanup...${NC}"
    echo

    # Get VPC ID if we don't have it
    if [ -z "$VPC_ID" ]; then
        VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
            --filters "Name=tag:Project,Values=fineract" "Name=tag:Environment,Values=$ENV" \
            --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
    fi

    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        echo -e "${BLUE}→ Final cleanup for VPC: $VPC_ID${NC}"

        # Delete all ENIs (force)
        echo -e "${BLUE}  Cleaning up remaining ENIs...${NC}"
        cleanup_all_enis_in_vpc "$VPC_ID" "$AWS_REGION"

        # Delete all Security Groups (force)
        echo -e "${BLUE}  Cleaning up remaining Security Groups...${NC}"
        cleanup_security_groups_with_retry "$VPC_ID" "$AWS_REGION"

        # Delete all subnets
        echo -e "${BLUE}  Cleaning up remaining Subnets...${NC}"
        SUBNETS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "Subnets[].SubnetId" --output text 2>/dev/null || echo "")

        if [ -n "$SUBNETS" ]; then
            for subnet_id in $SUBNETS; do
                retry_with_backoff \
                    "aws ec2 delete-subnet --region $AWS_REGION --subnet-id $subnet_id" \
                    "Delete subnet $subnet_id" || true
            done
        fi

        # Delete route tables (non-main)
        echo -e "${BLUE}  Cleaning up remaining Route Tables...${NC}"
        RT_IDS=$(aws ec2 describe-route-tables --region "$AWS_REGION" \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "RouteTables[?Associations[0].Main==\`false\`].RouteTableId" \
            --output text 2>/dev/null || echo "")

        if [ -n "$RT_IDS" ]; then
            for rt_id in $RT_IDS; do
                retry_with_backoff \
                    "aws ec2 delete-route-table --region $AWS_REGION --route-table-id $rt_id" \
                    "Delete route table $rt_id" || true
            done
        fi

        # Detach and delete Internet Gateway
        echo -e "${BLUE}  Cleaning up Internet Gateway...${NC}"
        IGW_ID=$(aws ec2 describe-internet-gateways --region "$AWS_REGION" \
            --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
            --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "")

        if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
            aws ec2 detach-internet-gateway --region "$AWS_REGION" \
                --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" 2>/dev/null || true
            sleep 10
            retry_with_backoff \
                "aws ec2 delete-internet-gateway --region $AWS_REGION --internet-gateway-id $IGW_ID" \
                "Delete Internet Gateway $IGW_ID" || true
        fi

        # Final VPC deletion attempt
        echo -e "${BLUE}  Final VPC deletion attempt...${NC}"
        retry_with_backoff \
            "aws ec2 delete-vpc --region $AWS_REGION --vpc-id $VPC_ID" \
            "Delete VPC $VPC_ID" || {
                echo -e "${RED}  ✗ Failed to delete VPC after final cleanup${NC}"
                echo -e "${YELLOW}  Manual cleanup may be required in AWS Console${NC}"
            }
    fi

    echo
fi

# Cleanup temporary files
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 7: Cleanup...${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# Remove destroy plan
rm -f destroy.tfplan

echo -e "${GREEN}✓ Cleaned up temporary files${NC}"
echo

# Enhanced Summary Report
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    Destruction Complete!                       ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo
echo "Summary:"
echo "  Environment: ${ENV}"
echo "  Total Duration: ${DESTROY_DURATION}s ($(($DESTROY_DURATION / 60)) minutes)"
echo "  Destroy Attempts: $DESTROY_ATTEMPT"
echo "  Final Status: $([ "$DESTROY_SUCCESS" = true ] && echo "✓ Success" || echo "✗ Failed")"
echo "  State backup: ${BACKUP_DIR}"
echo
echo "Cost Savings:"
echo "  Monthly: ~${MONTHLY_COST}"
echo "  Yearly: ~${YEARLY_COST}"
echo

if [ ${#FAILED_RESOURCES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Resources that failed to delete:${NC}"
    for resource in "${FAILED_RESOURCES[@]}"; do
        echo -e "${YELLOW}  - $resource${NC}"
    done
    echo
    echo -e "${YELLOW}Manual cleanup commands:${NC}"
    if [ -n "$VPC_ID" ]; then
        echo "  # Delete VPC manually:"
        echo "  aws ec2 delete-vpc --region $AWS_REGION --vpc-id $VPC_ID"
    fi
    echo "  # List all fineract resources:"
    echo "  aws resourcegroupstaggingapi get-resources --region $AWS_REGION --tag-filters Key=Project,Values=fineract Key=Environment,Values=$ENV"
    echo
fi

echo -e "${BLUE}Important Notes:${NC}"
echo "1. Some resources (RDS, Secrets Manager) may take 10-15 minutes to fully delete"
echo "2. Secrets Manager secrets are marked for deletion (30-day recovery period)"
echo "3. Check AWS Console in 24-48 hours to verify cost savings"
echo "4. Terraform state backed up to: $BACKUP_DIR"
echo
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Verify no unexpected charges in AWS Cost Explorer"
echo "2. Check AWS Console for any remaining resources"
echo "3. Remove local Terraform state if done:"
echo "   rm -f terraform.tfstate*"
echo
if [ "$DESTROY_SUCCESS" = true ] && [ "$VERIFICATION_FAILED" = false ]; then
    echo -e "${GREEN}✓ All resources successfully destroyed!${NC}"
else
    echo -e "${YELLOW}⚠ Destruction completed with warnings. Review the summary above.${NC}"
fi
echo
