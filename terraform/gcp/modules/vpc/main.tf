# ==============================================================================
# GCP VPC Module
# Creates VPC, subnets, Cloud NAT, and firewall rules for GKE
# ==============================================================================

# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-${var.environment}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Primary subnet for GKE nodes
resource "google_compute_subnetwork" "gke" {
  name          = "${var.cluster_name}-${var.environment}-gke-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.subnet_cidr

  # Enable Private Google Access for cost optimization
  private_ip_google_access = var.enable_private_google_access

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "${var.cluster_name}-pods"
    ip_cidr_range = var.pods_range_cidr
  }

  secondary_ip_range {
    range_name    = "${var.cluster_name}-services"
    ip_cidr_range = var.services_range_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for Cloud NAT
resource "google_compute_router" "main" {
  name    = "${var.cluster_name}-${var.environment}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = 64514
  }
}

# Cloud NAT for outbound internet access from private nodes
resource "google_compute_router_nat" "main" {
  name                               = "${var.cluster_name}-${var.environment}-nat"
  project                            = var.project_id
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  # Cost optimization: Limit NAT ports per VM
  min_ports_per_vm = 64
}

# Firewall rule: Allow internal communication within VPC
resource "google_compute_firewall" "internal" {
  name    = "${var.cluster_name}-${var.environment}-allow-internal"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_range_cidr,
    var.services_range_cidr
  ]

  priority = 1000
}

# Firewall rule: Allow health checks from Google Load Balancers
resource "google_compute_firewall" "health_checks" {
  name    = "${var.cluster_name}-${var.environment}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
  }

  # Google health check ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["gke-${var.cluster_name}-${var.environment}"]
  priority    = 1000
}

# Firewall rule: Allow SSH for debugging (optional, restricted)
resource "google_compute_firewall" "ssh" {
  name    = "${var.cluster_name}-${var.environment}-allow-ssh"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP (Identity-Aware Proxy) range for secure SSH
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["gke-${var.cluster_name}-${var.environment}"]
  priority    = 1000
}
