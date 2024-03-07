# -------------------------------------------------------------------------------------
# Create Spoke VPC networks.
# -------------------------------------------------------------------------------------

module "vpc_spoke1" {
  source                                 = "terraform-google-modules/network/google"
  count                                  = (var.create_spoke_networks ? 1 : 0)
  version                                = "~> 9.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}spoke1-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-spoke1"
      subnet_ip     = var.cidr_spoke1
      subnet_region = var.region
    }
  ]

  routes = [
    {
      name              = "${local.prefix}spoke1-to-ilbnh"
      description       = "Default route to VM-Series NGFW"
      destination_range = "0.0.0.0/0"
      next_hop_ilb      = module.lb_internal.address
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-spoke1"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}


module "vpc_spoke2" {
  source                                 = "terraform-google-modules/network/google"
  count                                  = (var.create_spoke_networks ? 1 : 0)
  version                                = "~> 9.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}spoke2-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-spoke2"
      subnet_ip     = var.cidr_spoke2
      subnet_region = var.region
    }
  ]

  routes = [
    {
      name              = "${local.prefix}spoke2-to-ilbnh"
      description       = "Default route to VM-Series NGFW"
      destination_range = "0.0.0.0/0"
      next_hop_ilb      = module.lb_internal.address
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-spoke2"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}



# -------------------------------------------------------------------------------------
# Create policy based routes to inspect intra-VPC traffic within each spoke VPC.
# -------------------------------------------------------------------------------------

resource "google_network_connectivity_policy_based_route" "pbr_spoke1" {
  provider        = google-beta
  count           = (var.create_spoke_networks ? 1 : 0)
  name            = "${local.prefix}intravpc-spoke1"
  network         = module.vpc_spoke1[0].network_id
  next_hop_ilb_ip = module.lb_internal.address
  priority        = 10

  filter {
    protocol_version = "IPV4"
    ip_protocol      = "ALL"
    src_range        = var.cidr_spoke1
    dest_range       = var.cidr_spoke1
  }
}


resource "google_network_connectivity_policy_based_route" "pbr_spoke2" {
  provider        = google-beta
  count           = (var.create_spoke_networks ? 1 : 0)
  name            = "${local.prefix}intravpc-spoke2"
  network         = module.vpc_spoke2[0].network_id
  next_hop_ilb_ip = module.lb_internal.address
  priority        = 10

  filter {
    protocol_version = "IPV4"
    ip_protocol      = "ALL"
    src_range        = var.cidr_spoke2
    dest_range       = var.cidr_spoke2
  }
}



# -------------------------------------------------------------------------------------
# Create VPC peering connections between the trust and spoke networks.
# -------------------------------------------------------------------------------------

module "peering_spoke1" {
  source                                    = "terraform-google-modules/network/google//modules/network-peering"
  count                                     = (var.create_spoke_networks ? 1 : 0)
  version                                   = "~> 9.0"
  local_network                             = module.vpc_trust.network_id
  peer_network                              = module.vpc_spoke1[0].network_id
  export_local_subnet_routes_with_public_ip = false
}


module "peering_spoke2" {
  source                                    = "terraform-google-modules/network/google//modules/network-peering"
  count                                     = (var.create_spoke_networks ? 1 : 0)
  version                                   = "~> 9.0"
  local_network                             = module.vpc_trust.network_id
  peer_network                              = module.vpc_spoke2[0].network_id
  export_local_subnet_routes_with_public_ip = false

  module_depends_on = [
    module.peering_spoke1[0].complete
  ]
}



# -------------------------------------------------------------------------------------
# Create Spoke VM Ubuntu instances for testing inspection flows.
# -------------------------------------------------------------------------------------

resource "google_compute_instance" "spoke1_vm" {
  count                     = (var.create_spoke_networks ? 1 : 0)
  name                      = "${local.prefix}spoke1-vm1"
  machine_type              = "n2-standard-2"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "${var.spoke_vm_user}:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = module.vpc_spoke1[0].subnets_self_links[0]
    network_ip = cidrhost(var.cidr_spoke1, 10)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-jenkins"
    }
  }

  service_account {
    scopes = var.spoke_vm_scopes
  }
}


resource "google_compute_instance" "spoke2_vm1" {
  count                     = (var.create_spoke_networks ? 1 : 0)
  name                      = "${local.prefix}spoke2-vm1"
  machine_type              = "f1-micro"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "${var.spoke_vm_user}:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = module.vpc_spoke2[0].subnets_self_links[0]
    network_ip = cidrhost(var.cidr_spoke2, 10)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-apache"
    }
  }

  service_account {
    scopes = var.spoke_vm_scopes
  }
}


resource "google_compute_instance" "spoke2_vm2" {
  count                     = (var.create_spoke_networks ? 1 : 0)
  name                      = "${local.prefix}spoke2-vm2"
  machine_type              = "f1-micro"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "${var.spoke_vm_user}:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = module.vpc_spoke2[0].subnets_self_links[0]
    network_ip = cidrhost(var.cidr_spoke2, 11)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-apache"
    }
  }

  service_account {
    scopes = var.spoke_vm_scopes
  }
}