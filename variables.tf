# -------------------------------------------------------------------------------------
# Required variables
# -------------------------------------------------------------------------------------

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "public_key_path" {
  description = "Local path to public SSH key. To generate the key pair use `ssh-keygen -t rsa -C admin -N '' -f id_rsa`  If you do not have a public key, run `ssh-keygen -f ~/.ssh/demo-key -t rsa -C admin`"
  type        = string
}

variable "mgmt_allow_ips" {
  description = "A list of IP addresses to be added to the management network's ingress firewall rule. The IP addresses will be able to access to the VM-Series management interface."
  type        = list(string)
}

variable "region" {
  description = "GCP Region"
  type        = string
}



# -------------------------------------------------------------------------------------
# Optional variables
# -------------------------------------------------------------------------------------
variable "panorama_ip" {
  description = "IP address of Panorama to centrally manage the VM-Series."
  default     = null
  type        = string
}

variable "panorama_dg" {
  description = "Panorama Device Group to bootstrap the VM-Series."
  default     = null
  type        = string
}

variable "panorama_ts" {
  description = "Panorama Template Stack to bootstrap the VM-Series."
  default     = null
  type        = string
}

variable "panorama_auth_key" {
  description = "Panorama Auth key to authenticate the VM-Sereis as a managed device."
  default     = null
  type        = string
}

variable "vmseries_image_name" {
  description = "Name of the VM-Series image within the paloaltonetworksgcp-public project.  To list available images, run: `gcloud compute images list --project paloaltonetworksgcp-public --no-standard-images`. If you are using a custom image in a different project, please update `local.vmseries_iamge_url` in `main.tf`."
  default     = "vmseries-flex-bundle2-1022h2"
  type        = string
}

variable "vmseries_machine_type" {
  description = "The machine shape for the VM-Series instance (N2 and E2 instances are supported)."
  default     = "n2-standard-4"
  type        = string
}

variable "vmseries_min_cpu_platform" {
  description = "The minimum CPU platform for the machine type."
  default     = "Intel Cascade Lake"
  type        = string
}

variable "vmseries_replica_minimum" {
  description = "The max number of firewalls to run in each region."
  default     = 1
  type        = number
}

variable "vmseries_replica_maximum" {
  description = "The minimum number of firewalls to run in each region."
  default     = 1
  type        = number
}

variable "prefix" {
  description = "Prefix to GCP resource names, an arbitrary string"
  default     = null
  type        = string
}

variable "autoscaler_metrics" {
  description = <<-EOF
  The map with the keys being metrics identifiers (e.g. custom.googleapis.com/VMSeries/panSessionUtilization).
  Each of the contained objects has attribute `target` which is a numerical threshold for a scale-out or a scale-in.
  Each zonal group grows until it satisfies all the targets.  Additional optional attribute `type` defines the 
  metric as either `GAUGE` (the default), `DELTA_PER_SECOND`, or `DELTA_PER_MINUTE`. For full specification, see 
  the `metric` inside the [provider doc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_autoscaler).
  EOF
  default = {
    "custom.googleapis.com/VMSeries/panSessionActive" = {
      target = 100
    }
  }
}

variable "enable_session_resiliency" {
  description = "If true, a Memorystore Redis Cluster will be created to store session information across the VM-Series firewalls"
  type        = bool
  default     = false
}

variable "cidr_mgmt" {
  description = "The CIDR range of the management subnetwork."
  type        = string
  default     = "10.0.0.0/28"
}

variable "cidr_untrust" {
  description = "The CIDR range of the untrust subnetwork."
  type        = string
  default     = "10.0.1.0/28"
}

variable "cidr_trust" {
  description = "The CIDR range of the trust subnetwork."
  type        = string
  default     = "10.0.2.0/28"
}

variable "create_monitoring_dashboard" {
  description = "Set to 'true' to create a custom Google Cloud Monitoring dashboard for VM-Series metrics."
  type        = bool
  default     = true
}

variable "create_spoke_networks" {
  description = <<-EOF
  Set to 'true' to create two spoke networks.  The spoke networks will be connected to the hub network via VPC
  Peering and each network will have a single Ubuntu instance for testing inspection flows. 
  Set to 'false' to skip spoke network creation. 
  EOF
  type        = bool
  default     = true
}

variable "cidr_spoke1" {
  description = "The CIDR range of the management subnetwork."
  type        = string
  default     = "10.1.0.0/28"
}

variable "cidr_spoke2" {
  description = "The CIDR range of the spoke1 subnetwork."
  type        = string
  default     = "10.2.0.0/28"
}

variable "spoke_vm_user" {
  description = "The username for the compute instance in the spoke networks."
  type        = string
  default     = "paloalto"
}

variable "spoke_vm_scopes" {
  description = "A list of service scopes. Both OAuth2 URLs and gcloud short names are supported. To allow full access to all Cloud APIs, use the cloud-platform"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write"
  ]
}