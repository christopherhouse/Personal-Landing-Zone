output "vm_name" {
  description = "Name of the validation VM."
  value       = local.vm_name
}

output "vm_resource_id" {
  description = "Resource ID of the validation VM."
  value       = module.vm.resource_id
}

output "storage_account_name" {
  description = "Name of the validation storage account."
  value       = local.storage_account_name
}

output "blob_private_endpoint_fqdn" {
  description = "FQDN that resolves to the blob private endpoint (used by quickstart.md Part 1 nslookup step)."
  value       = "${local.storage_account_name}.blob.core.windows.net"
}
