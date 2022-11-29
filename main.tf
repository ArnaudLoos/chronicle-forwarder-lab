terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.44.1"
    }
  }
}

provider "google" {
  project = "${var.project_id}"
}

#Enable the Compute API (or do it manually beforehand)
#There is a delay between the time you enable the API and being able to deploy resources
#resource "google_project_service" "compute-api" {
#  project = "${var.project_id}"
#  service = "compute.googleapis.com"
#}

# Create a network
resource "google_compute_network" "default-network" {
  name                    = "default-network"
  auto_create_subnetworks = false
}

#Create a subnet within that network
resource "google_compute_subnetwork" "default-subnet" {
  name          = "default-subnet"
  ip_cidr_range = "10.2.0.0/16"
  region        = "${var.region}"
  network       = google_compute_network.default-network.id
}

#Allow ICMP firewall rule
resource "google_compute_firewall" "allow-icmp" {
  name = "allow-icmp"
  network = google_compute_network.default-network.name
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

#Allow SSH firewall rule
resource "google_compute_firewall" "allow-ssh" {
  name = "allow-ssh"
  network = google_compute_network.default-network.name
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
  target_tags = ["forwarder"]
  source_ranges = ["0.0.0.0/0"]
}

#Allow RDP to Windows hosts firewall rule
resource "google_compute_firewall" "allow-rdp" {
  name = "allow-rdp"
  network = google_compute_network.default-network.name
  allow {
    protocol = "tcp"
    ports = ["3389"]
  }
  target_tags = ["windows"]
  source_ranges = ["0.0.0.0/0"]
}

#Allow Syslog being sent to the Forwarder on any 3xxx port number
resource "google_compute_firewall" "allow-syslog" {
  name = "allow-syslog"
  network = google_compute_network.default-network.name
  allow {
    protocol = "tcp"
    ports = ["3000-4000"]
  }
  source_tags = ["windows"]
  target_tags = ["forwarder"]
}

#Set a Router on our network
resource "google_compute_router" "default-router" {
  name    = "default-router"
  region  = google_compute_subnetwork.default-subnet.region
  network = google_compute_network.default-network.id

  bgp {
    asn = 64514
  }
}

#Setup Cloud NAT
resource "google_compute_router_nat" "default-router-nat" {
  name                               = "default-router-nat"
  router                             = google_compute_router.default-router.name
  region                             = google_compute_router.default-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#Deploy the Linux host which will run the Chronicle Forwarder Docker container
resource "google_compute_instance" "compute-debian" {
#  count        = 1
#  name         = "dev-vm${count.index + 1}"
  name         = "chronicle-forwarder"
  project      = "${var.project_id}"
  machine_type = "${var.instance_type}"
  zone         = "${var.zone}"

  tags = ["forwarder"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      labels = {
        my_label = "debian"
      }
    }
  }
  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }
  network_interface {
    subnetwork = google_compute_subnetwork.default-subnet.id
  }
  allow_stopping_for_update = true
}

#Deploy our Windows host to send logs to the Forwarder
resource "google_compute_instance" "compute-windows" {
  name         = "windows-vm"
  project      = "${var.project_id}"
  machine_type = "${var.instance_type}"
  zone         = "${var.zone}"

  tags = ["windows"]

  boot_disk {
    initialize_params {
      image = "windows-cloud/windows-2022"
    }
  }
  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }
  network_interface {
    subnetwork = google_compute_subnetwork.default-subnet.id
    access_config {}  # Will assign an external IP for RDP access. If you get an error about this it probably means an Org Policy is preventing it.
  }
  allow_stopping_for_update = true
}
