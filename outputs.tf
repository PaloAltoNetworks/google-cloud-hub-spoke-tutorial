output "EXTERNAL_LB_IP" {
  description = "External load balancer's frontend address that distributes internet traffic to VM-Series untrust interfaces."
  value       = module.lb_external.ip_addresses["rule1"]
}