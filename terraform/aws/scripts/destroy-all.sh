#!/usr/bin/env python3
#
# Terraform Destroy Script
# Simplified and robust
#

import subprocess
import sys
import json
import os

# Configuration
def get_env_var(env, var_name, default):
    """Get environment variable from Terraform config"""
    try:
        result = subprocess.run(
            ['grep', '-E', f'^{var_name}[[:space:]]*=', f'{env}/{env}-eks.tfvars'],
            capture_output=True,
            text=True,
            cwd='/Users/guymoyo/dev/fineract-gitops/terraform/aws'
        )
        if result.returncode == 0:
            # Extract value after '='
            output = result.stdout.strip()
            if '=' in output:
                value = output.split('=', 1)[-1].strip().strip()
                return value
            else:
                return default
        else:
            return default
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return default

def run_terraform_command(cmd, cwd):
    """Run terraform command and return output"""
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        capture_error=True,
        cwd=cwd,
        text=True
    )
    return result.returncode, result.stdout, result.stderr

def remove_stale_locks(env, region):
    """Remove stale Terraform state locks from DynamoDB"""
    table = f"fineract-gitops-tf-lock-2026"
    
    try:
        result = subprocess.run(
            ['aws', 'dynamodb', 'scan', '--table-name', table, '--region', region, '--output', 'json'],
            capture_output=True
        )
        
        if result.returncode == 0:
            try:
                data = json.loads(result.stdout)
                locks = data.get('Items', [])
                
                removed_count = 0
                for item in locks:
                    lock_id = item.get('LockID', {}).get('S', '')
                    if env in lock_id and 'MacBookPro' in item.get('Info', {}).get('Who', ''):
                        removed_count += 1
                        print(f"Removing lock: {lock_id}")
                        
                        key = json.dumps({
                            '"'"'"'S'"'"'"'": lock_id,
                            '"'"'"'Digest'"'"'": item.get('Digest', {}).get('S', '')
                        })
                        
                        delete_result = subprocess.run(
                            ['aws', 'dynamodb', 'delete-item',
                                '--table-name', table,
                                '--region', region,
                                '--key', key],
                                capture_output=True,
                                capture_error=True
                            ]
                        )
                        
                        if delete_result.returncode == 0:
                            print(f"  ✓ Successfully deleted")
                            removed_count += 1
                        else:
                            print(f"  Failed (may already be deleted)")
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
        
        print(f"  Removed {removed_count} stale lock(s)")
        
    except Exception as e:
        print(f"Error scanning DynamoDB: {e}", file=sys.stderr)

def destroy_terraform(env, force=False):
    """Destroy Terraform resources"""
    # Change to terraform directory
    tf_dir = '/Users/guymoyo/dev/fineract-gitops/terraform/aws'
    os.chdir(tf_dir)
    
    # Initialize if needed
    if not os.path.exists('.terraform'):
        print("Initializing Terraform...")
        code, _, err = run_terraform_command(['terraform', 'init'], tf_dir)
        if code != 0:
            print(f"  Error: {err}", file=sys.stderr)
            return False
    else:
        print("  Already initialized")
    
    # Generate destroy plan
    print("Generating destroy plan...")
    code, out, err = run_terraform_command(
        ['terraform', 'plan', '-destroy', '-refresh=false', 
         '-var-file', f'environments/{env}-eks.tfvars',
         '-out', 'destroy.tfplan'],
        tf_dir
    )
    
    if code != 0:
        print(f"Error: {err}", file=sys.stderr)
        return False
    
    # Count resources
    try:
        plan_json = json.loads(out)
        resource_count = len(plan_json.get('resource_changes', {}))
        print(f"  Resources to destroy: {resource_count}")
    except Exception as e:
        print(f"Error counting resources: {e}", file=sys.stderr)
        resource_count = 0
    
    print("")
    print("AWS Resources:")
    print("  • EKS Kubernetes cluster")
    print("  • RDS PostgreSQL instances")
    print("  • S3 buckets (and ALL data)")
    print("  • VPC, subnets, security groups")
    print("  • NAT Gateway and Elastic IPs")
    print("  • IAM roles and policies")
    print("  • AWS Secrets Manager secrets")
    print("  • CloudWatch Log Groups")
    print("")
    print("Kubernetes Resources:")
    print("  • Namespace: fineract-{env}")
    print("  • All deployments, statefulsets, services")
    print("  • All ConfigMaps, Secrets")
    print("  • All Persistent Volume Claims")
    print("")
    
    # Show plan
    print("")
    if force:
        print("Skipping confirmation and waiting")
        print("Using: terraform destroy -auto-approve -refresh-only -lock=false")
    else:
        print("Please type 'yes' to confirm destruction or Ctrl+C to cancel")
        try:
            confirmation = input("Confirm destroy (yes/no): ")
            if confirmation.lower() != 'yes':
                print("Destroy cancelled")
                return False
        except (EOFError, KeyboardInterrupt):
            print("Destroy cancelled")
            return False
    
    print("")
    print("Destroying...")
    
    if force:
        cmd = ['terraform', 'apply', '-auto-approve', '-refresh-only', '-lock=false', 'destroy.tfplan']
    else:
        cmd = ['terraform', 'apply', '-refresh=false', 'destroy.tfplan']
    
    code, _, err = run_terraform_command(cmd, tf_dir)
    
    if code == 0:
        print("✓ Terraform destroy completed successfully")
        return True
    else:
        print(f"✗ Terraform destroy failed with code: {code}")
        return False

def main():
    import sys
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/destroy-all.sh <environment> [--force]")
        print("")
        print("Arguments:")
        print("  environment    Target environment (dev, uat, production)")
        print("  --force       Force destroy without waiting")
        print("")
        print("Examples:")
        print("  python3 scripts/destroy-all.sh dev")
        print("  python3 scripts/destroy-all.sh dev --force")
        sys.exit(1)
    
    env = sys.argv[1]
    
    if env not in ['dev', 'uat', 'production']:
        print(f"Error: Invalid environment '{env}'")
        sys.exit(1)
    
    print(f"")
    print(f"========================================")
    print(f"  Terraform Destroy - {env}")
    print(f"========================================")
    
    # Get region from Terraform config
    region = get_env_var(env, 'region', 'eu-central-1', 'eu-central-1')
    
    # Step 1: Remove stale locks
    print("Removing stale Terraform state locks...")
    remove_stale_locks(env, region)
    
    # Step 2: Destroy Terraform
    print("")
    print(f"Destroying Terraform resources in {env}...")
    success = destroy_terraform(env, '--force' in sys.argv)
    
    # Summary
    print(f"")
    print(f"========================================")
    print(f"  Destroy Complete!")
    print(f"========================================")
    print(f"Environment: {env}")
    print(f"Success: {success}")
    print(f"")
    print("Next steps to redeploy:")
    print("   1. Deploy Infrastructure:")
    print(f"     cd terraform/aws")
    print("     terraform init")
    print("     terraform apply -var-file=environments/{env}-eks.tfvars")
    print("")
    print("  2. Deploy Applications:")
    print("     ./scripts/wait-for-lb-and-sync.sh {env}")
    print("")
    print("Done!")

if __name__ == '__main__':
    main()
