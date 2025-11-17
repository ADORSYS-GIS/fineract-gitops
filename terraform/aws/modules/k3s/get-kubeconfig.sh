#!/bin/bash
# Script to retrieve kubeconfig from K3s server
# Used by Terraform external data source

# Parse input JSON
eval "$(jq -r '@sh "SERVER_IP=\(.server_ip) K3S_TOKEN=\(.k3s_token) CLUSTER_NAME=\(.cluster_name)"')"

# Wait for K3s to be ready (retry for up to 5 minutes)
for i in {1..60}; do
  if nc -z "$SERVER_IP" 6443 2>/dev/null; then
    break
  fi
  sleep 5
done

# Generate kubeconfig
cat <<EOF | jq -c .
{
  "kubeconfig": "apiVersion: v1\nclusters:\n- cluster:\n    insecure-skip-tls-verify: true\n    server: https://${SERVER_IP}:6443\n  name: ${CLUSTER_NAME}\ncontexts:\n- context:\n    cluster: ${CLUSTER_NAME}\n    user: ${CLUSTER_NAME}\n  name: ${CLUSTER_NAME}\ncurrent-context: ${CLUSTER_NAME}\nkind: Config\npreferences: {}\nusers:\n- name: ${CLUSTER_NAME}\n  user:\n    token: ${K3S_TOKEN}\n"
}
EOF
