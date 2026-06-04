output "vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = module.vnet.resource_id
}

output "vnet_name" {
  description = "Name of the spoke VNet."
  value       = local.spoke_vnet_name
}

output "workload_subnet_id" {
  description = "Resource ID of the spoke's single workload subnet."
  value       = module.vnet.subnets["workload"].resource_id
}

output "resource_group_name" {
  description = "Name of the spoke RG."
  value       = module.rg.name
}
