#!/bin/bash
# EKS Node Bootstrap Script
set -o xtrace

# Bootstrap the node to join the EKS cluster
/etc/eks/bootstrap.sh ${cluster_name} ${bootstrap_extra_args}
