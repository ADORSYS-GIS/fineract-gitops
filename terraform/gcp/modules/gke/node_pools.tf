# ==============================================================================
# GKE Node Pool Configuration
# ==============================================================================

# Primary node pool
resource "google_container_node_pool" "primary" {
  name     = "${var.cluster_name}-${var.environment}-primary"
  project  = var.project_id
  location = google_container_cluster.primary.location
  cluster  = google_container_cluster.primary.name

  # Node locations (zones)
  # For zonal cluster: inherits from cluster
  # For regional cluster: can specify specific zones
  node_locations = var.environment == "production" ? null : null

  # Autoscaling configuration
  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  # Initial count
  initial_node_count = var.node_desired_count

  # Node configuration
  node_config {
    # Machine type selection based on environment
    # e2-standard-2: 2 vCPU, 8 GB (cost-effective)
    # n2d-standard-4: 4 vCPU, 16 GB (AMD, production)
    machine_type = var.machine_type

    # Spot VMs for dev/uat (60-80% savings)
    # Note: spot replaces the older preemptible option
    spot = var.use_preemptible

    # Disk configuration
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    image_type   = "COS_CONTAINERD"

    # Service account for Workload Identity
    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity metadata
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Labels
    labels = {
      environment = var.environment
      node-pool   = "primary"
      preemptible = var.use_preemptible ? "true" : "false"
    }

    # Tags for firewall rules
    tags = [
      "gke-${var.cluster_name}-${var.environment}",
      "gke-node"
    ]

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded instance configuration (security)
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Resource labels on the node VM
    resource_labels = {
      environment  = var.environment
      node-pool    = "primary"
      cost-center  = var.cost_center
      billing-code = var.billing_code
    }
  }

  # Management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }

  lifecycle {
    ignore_changes = [
      # Ignore node count changes from autoscaler
      initial_node_count,
    ]
  }
}

# Optional: Dedicated node pool for batch workloads (cost optimization)
# This pool uses preemptible VMs and can scale to 0
resource "google_container_node_pool" "batch" {
  count = var.enable_batch_node_pool ? 1 : 0

  name     = "${var.cluster_name}-${var.environment}-batch"
  project  = var.project_id
  location = google_container_cluster.primary.location
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = 0
    max_node_count = 3
  }

  initial_node_count = 0

  node_config {
    machine_type = "e2-standard-4"
    spot         = true  # Spot VMs for batch workloads

    disk_size_gb = 50
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment   = var.environment
      node-pool     = "batch"
      preemptible   = "true"
      workload-type = "batch"
    }

    # Taint for batch workloads only
    taint {
      key    = "workload-type"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }

    tags = [
      "gke-${var.cluster_name}-${var.environment}",
      "gke-batch-node"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    resource_labels = {
      environment   = var.environment
      node-pool     = "batch"
      cost-center   = var.cost_center
      workload-type = "batch"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}
