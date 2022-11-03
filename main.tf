
locals {
  prefix             = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""
  vmseries_image_url = "https://www.googleapis.com/compute/v1/projects/paloaltonetworksgcp-public/global/images/${var.vmseries_image_name}"
}

# -------------------------------------------------------------------------------------
# Create MGMT, UNTRUST, and TRUST VPC networks.  
# -------------------------------------------------------------------------------------

module "vpc_mgmt" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 4.0"
  project_id   = var.project_id
  network_name = "${local.prefix}mgmt-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-mgmt"
      subnet_ip     = var.cidr_mgmt
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name        = "${local.prefix}vmseries-mgmt"
      direction   = "INGRESS"
      priority    = "100"
      description = "Allow ingress access to VM-Series management interface"
      ranges      = var.mgmt_allow_ips
      allow = [
        {
          protocol = "tcp"
          ports    = ["22", "443", "3978"]
        }
      ]
    }
  ]
}


module "vpc_untrust" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 4.0"
  project_id   = var.project_id
  network_name = "${local.prefix}untrust-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-untrust"
      subnet_ip     = var.cidr_untrust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}ingress-all-untrust"
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


module "vpc_trust" {
  source                                 = "terraform-google-modules/network/google"
  version                                = "~> 4.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}hub-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-trust"
      subnet_ip     = var.cidr_trust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}ingress-all-trust"
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


module "cloud_nat_untrust" {
  source        = "terraform-google-modules/cloud-nat/google"
  version       = "=1.2"
  name          = "${local.prefix}untrust-nat"
  router        = "${local.prefix}untrust-router"
  project_id    = var.project_id
  region        = var.region
  create_router = true
  network       = module.vpc_untrust.network_id
}



# -------------------------------------------------------------------------------------
# Create bootstrap bucket for VM-Series
# -------------------------------------------------------------------------------------

data "google_compute_subnetwork" "trust" {
  self_link = module.vpc_trust.subnets_self_links[0]
  region    = var.region
}


data "google_compute_subnetwork" "untrust" {
  self_link = module.vpc_untrust.subnets_self_links[0]
  region    = var.region
}


# Update bootstrap.xml to reflect any changes made to variables.tf.
data "template_file" "bootstrap" {
  template = file("bootstrap_files/bootstrap.template")

  vars = {
    gateway_trust   = data.google_compute_subnetwork.trust.gateway_address
    gateway_untrust = data.google_compute_subnetwork.untrust.gateway_address
    spoke1_cidr     = var.cidr_spoke1
    spoke2_cidr     = var.cidr_spoke2
    spoke1_vm1_ip   = cidrhost(var.cidr_spoke1, 10)
    spoke2_vm1_ip   = cidrhost(var.cidr_spoke2, 10)
  }
}


# Create the bootstrap.xml file.
resource "local_file" "bootstrap" {
  filename = "bootstrap_files/bootstrap.xml"
  content  = data.template_file.bootstrap.rendered
}


# Create the bootstrap storage bucket.
module "bootstrap" {
  source          = "PaloAltoNetworks/vmseries-modules/google//modules/bootstrap"
  service_account = module.iam_service_account.email
  files = {
    "bootstrap_files/init-cfg.txt"                               = "config/init-cfg.txt"
    "${local_file.bootstrap.filename}"                           = "config/bootstrap.xml"
    "bootstrap_files/content/panupv2-all-contents-8622-7593"     = "content/panupv2-all-contents-8622-7593"
    "bootstrap_files/content/panup-all-antivirus-4222-4735"      = "content/panup-all-antivirus-4222-4735"
    "bootstrap_files/content/panupv3-all-wildfire-703414-706774" = "content/panupv3-all-wildfire-703414-706774"
    "bootstrap_files/authcodes"                                  = "license/authcodes"
  }
}



# -------------------------------------------------------------------------------------
# Create VM-Series Regional Managed Instance Group for autoscaling.
# -------------------------------------------------------------------------------------

module "iam_service_account" {
  source             = "PaloAltoNetworks/vmseries-modules/google//modules/iam_service_account"
  service_account_id = "${local.prefix}vmseries-mig-sa"
}


module "vmseries" {
  source                 = "github.com/PaloAltoNetworks/terraform-google-vmseries-modules//modules/autoscale?ref=autoscale_regional_migs-update"
  name                   = "${local.prefix}vmseries"
  use_regional_mig       = true
  region                 = var.region
  min_vmseries_replicas  = var.vmseries_replica_minimum // min firewalls per zone.
  max_vmseries_replicas  = var.vmseries_replica_maximum // max firewalls per zone.
  image                  = local.vmseries_image_url
  create_pubsub_topic    = true
  target_pool_self_links = [module.lb_external.target_pool]
  service_account_email  = module.iam_service_account.email
  autoscaler_metrics     = var.autoscaler_metrics
  tags                   = ["vmseries-tutorial"]
  network_interfaces = [
    {
      subnetwork       = module.vpc_untrust.subnets_self_links[0]
      create_public_ip = false
    },
    {
      subnetwork       = module.vpc_mgmt.subnets_self_links[0]
      create_public_ip = true
    },
    {
      subnetwork       = module.vpc_trust.subnets_self_links[0]
      create_public_ip = false
    }
  ]

  metadata = {
    mgmt-interface-swap                  = "enable"
    vmseries-bootstrap-gce-storagebucket = module.bootstrap.bucket_name
    serial-port-enable                   = true
    ssh-keys                             = "admin:${file(var.public_key_path)}"
  }

  scopes = [
    "https://www.googleapis.com/auth/compute.readonly",
    "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write"
  ]

  depends_on = [
    module.bootstrap
  ]
}



# -------------------------------------------------------------------------------------
# Create Internal & External Network Load Balancers.
# -------------------------------------------------------------------------------------

module "lb_internal" {
  source              = "PaloAltoNetworks/vmseries-modules/google//modules/lb_internal"
  name                = "${local.prefix}vmseries-internal-lb"
  network             = module.vpc_trust.network_id
  subnetwork          = module.vpc_trust.subnets_self_links[0]
  health_check_port   = "80"
  allow_global_access = true
  all_ports           = true
  # health_check = google_compute_health_check.lb.self_link
  backends = {
    backend1 = module.vmseries.regional_instance_group_id
  }
}


module "lb_external" {
  source                         = "PaloAltoNetworks/vmseries-modules/google//modules/lb_external"
  name                           = "${local.prefix}vmseries-external-lb"
  health_check_http_port         = 80
  health_check_http_request_path = "/"

  rules = {
    "rule1" = { all_ports = true }
  }
}



# -------------------------------------------------------------------------------------
# Create custom monitoring dashboard for VM-Series utilization metrics.
# -------------------------------------------------------------------------------------

resource "google_monitoring_dashboard" "dashboard" {
  count          = (var.create_monitoring_dashboard ? 1 : 0)
  dashboard_json = templatefile("${path.root}/bootstrap_files/dashboard.json.tpl", { dashboard_name = "VM-Series Metrics" })

  lifecycle {
    ignore_changes = [
      dashboard_json
    ]
  }
}