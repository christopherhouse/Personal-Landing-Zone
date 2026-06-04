# Root outputs.
#
# These surface the values an operator needs to verify the deployment
# end-to-end (quickstart.md Part 1): which gateway to connect to, which DNS
# server IP to expect in the VPN profile, and which validation-workload
# names to test against.

output "deployment_app_client_id" {
  description = "Deployment Entra app client ID. Emitted by bootstrap.ps1; re-surfaced here so `tofu output` is a single place to look up what the apply pipeline authenticates as."
  value       = var.deployment_app_client_id
}

output "vpn_gateway_name" {
  description = "Name of the P2S VPN gateway. Used to download the VPN client profile via `az network vnet-gateway vpn-client generate`."
  value       = module.hub.vpn_gateway_name
}

output "vpn_client_address_pool" {
  description = "CIDR allocated to connected VPN clients."
  value       = var.platform.vpn_client_address_pool
}

output "resolver_inbound_endpoint_ip" {
  description = "DNS Private Resolver inbound endpoint IP — pushed to VPN clients via the gateway's vpn_client_configuration.additional_dns_servers."
  value       = module.hub.resolver_inbound_endpoint_ip
}

output "validation_vm_name" {
  description = "Name of the validation VM (null if no spoke sets include_validation_workload)."
  value = try(
    one([for _, w in module.validation_workload : w.vm_name]),
    null,
  )
}

output "validation_storage_account_name" {
  description = "Name of the validation storage account (null if no spoke sets include_validation_workload)."
  value = try(
    one([for _, w in module.validation_workload : w.storage_account_name]),
    null,
  )
}

output "validation_blob_private_endpoint_fqdn" {
  description = "FQDN that resolves to the validation storage account's blob private endpoint (null if no spoke sets include_validation_workload)."
  value = try(
    one([for _, w in module.validation_workload : w.blob_private_endpoint_fqdn]),
    null,
  )
}
