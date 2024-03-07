
locals {
  prefix             = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""
  vmseries_image_url = "https://www.googleapis.com/compute/v1/projects/paloaltonetworksgcp-public/global/images/${var.vmseries_image_name}"
}


# -------------------------------------------------------------------------------------
# Create MGMT, UNTRUST, and TRUST VPC networks.  
# -------------------------------------------------------------------------------------

module "vpc_mgmt" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 9.0"
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
  version      = "~> 9.0"
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
  version                                = "~> 9.0"
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
  version       = "~> 5.0"
  name          = "${local.prefix}untrust-nat"
  router        = "${local.prefix}untrust-router"
  project_id    = var.project_id
  region        = var.region
  create_router = true
  network       = module.vpc_untrust.network_id
}



# -------------------------------------------------------------------------------------
# Enable session resiliency with Memorystore Redis
# -------------------------------------------------------------------------------------

resource "google_redis_instance" "main" {
  count                   = (var.enable_session_resiliency ? 1 : 0)
  name                    = "${local.prefix}vmseries-redis"
  project                 = var.project_id
  region                  = var.region
  tier                    = "STANDARD_HA"
  memory_size_gb          = 5
  replica_count           = 1
  auth_enabled            = true
  redis_version           = "REDIS_7_0"
  connect_mode            = "DIRECT_PEERING"
  read_replicas_mode      = "READ_REPLICAS_ENABLED"
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  authorized_network      = module.vpc_mgmt.network_self_link
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


// Update bootstrap.xml to reflect any changes made to variables.tf.
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


// Create the bootstrap.xml file.
resource "local_file" "bootstrap" {
  filename = "bootstrap_files/bootstrap.xml"
  content  = data.template_file.bootstrap.rendered
}


// Create the bootstrap storage bucket.
module "bootstrap" {
  source          = "PaloAltoNetworks/swfw-modules/google//modules/bootstrap"
  version         = "~> 2.0"
  service_account = module.iam_service_account.email
  location        = "US"
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
  source             = "PaloAltoNetworks/swfw-modules/google//modules/iam_service_account"
  version            = "~> 2.0"
  service_account_id = "${local.prefix}vmseries-mig-sa"
  project_id         = var.project_id
}


module "vmseries" {
  source                = "PaloAltoNetworks/swfw-modules/google//modules/autoscale"
  version               = "~> 2.0"
  name                  = "${local.prefix}vmseries"
  regional_mig          = true
  region                = var.region
  min_vmseries_replicas = var.vmseries_replica_minimum // min firewalls per zone.
  max_vmseries_replicas = var.vmseries_replica_maximum // max firewalls per zone.
  image                 = local.vmseries_image_url
  create_pubsub_topic   = false
  target_pools          = [module.lb_external.target_pool]
  service_account_email = module.iam_service_account.email
  autoscaler_metrics    = var.autoscaler_metrics
  tags                  = ["vmseries-tutorial"]
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
    serial-port-enable                   = true
    ssh-keys                             = "admin:${file(var.public_key_path)}"
    redis-endpoint                       = var.enable_session_resiliency ? "${google_redis_instance.main[0].host}:${google_redis_instance.main[0].port}" : ""
    redis-auth                           = var.enable_session_resiliency ? "${google_redis_instance.main[0].auth_string}" : ""
    plugin-op-commands                   = var.enable_session_resiliency ? "set-sess-ress:True" : ""
    vmseries-bootstrap-gce-storagebucket = var.panorama_ip == null ? module.bootstrap.bucket_name : "" // If Panorama IP is not provided, use to GSC to bootstrap
    panorama-server                      = var.panorama_ip
    dgname                               = var.panorama_dg
    tplname                              = var.panorama_ts
    vm-auth-key                          = var.panorama_auth_key
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
  source                          = "PaloAltoNetworks/swfw-modules/google//modules/lb_internal"
  version                         = "~> 2.0"
  name                            = "${local.prefix}vmseries-internal-lb"
  region                          = var.region
  project                         = var.project_id
  network                         = module.vpc_trust.network_id
  subnetwork                      = module.vpc_trust.subnets_self_links[0]
  health_check_port               = "80"
  allow_global_access             = true
  all_ports                       = true
  connection_draining_timeout_sec = 30

  connection_tracking_policy = {
    mode                              = "PER_CONNECTION"
    persistence_on_unhealthy_backends = "NEVER_PERSIST"
  }
  backends = {
    backend1 = module.vmseries.regional_instance_group_id
  }
}


module "lb_external" {
  source                         = "PaloAltoNetworks/swfw-modules/google//modules/lb_external"
  version                        = "~> 2.0"
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
