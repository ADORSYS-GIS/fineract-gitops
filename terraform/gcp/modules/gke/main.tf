# ==============================================================================
# GKE Cluster Module
# Creates a GKE Standard cluster with Workload Identity
# ==============================================================================

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.cluster_name}-${var.environment}"
  project  = var.project_id

  # Location: Use zone for dev (cost optimization), region for production (HA)
  location = var.environment == "production" ? var.region : var.zone

  # Remove default node pool and use separately managed node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Allow public API access
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Workload Identity configuration (GCP equivalent of AWS IRSA)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Master authorized networks (restrict API access)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks (restrict in production)"
    }
  }

  # Cluster add-ons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  # Release channel for automatic upgrades
  release_channel {
    channel = var.environment == "production" ? "STABLE" : "REGULAR"
  }

  # Maintenance window (daily 3-7 AM UTC for dev/uat, Sunday only for production)
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T03:00:00Z"
      end_time   = "2024-01-01T07:00:00Z"
      recurrence = var.environment == "production" ? "FREQ=WEEKLY;BYDAY=SA,SU" : "FREQ=DAILY"
    }
  }

  # Binary Authorization (optional, for production)
  dynamic "binary_authorization" {
    for_each = var.environment == "production" ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Resource labels for cost tracking
  resource_labels = merge(var.labels, {
    environment  = var.environment
    cost-center  = var.cost_center
    billing-code = var.billing_code
    managed-by   = "terraform"
  })

  # Deletion protection (enable for production)
  deletion_protection = var.environment == "production"

  lifecycle {
    ignore_changes = [
      # Ignore changes to node_config as we manage node pools separately
      node_config,
    ]
  }
}
