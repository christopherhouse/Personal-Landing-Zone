output "vnet_id" {
  description = "Resource ID of the hub VNet."
  value       = module.vnet.resource_id
}

output "vnet_name" {
  description = "Name of the hub VNet."
  value       = local.hub_vnet_name
}

output "gateway_subnet_id" {
  description = "Resource ID of the GatewaySubnet."
  value       = module.vnet.subnets["gateway"].resource_id
}

output "vpn_gateway_id" {
  description = "Resource ID of the P2S VPN gateway."
  value       = azurerm_virtual_network_gateway.vpn.id
}

output "vpn_gateway_name" {
  description = "Name of the P2S VPN gateway."
  value       = azurerm_virtual_network_gateway.vpn.name
}

output "resolver_inbound_endpoint_ip" {
  description = "Private IP of the DNS Private Resolver inbound endpoint. Pinned to a Static value so spoke VNets can hardcode it as their dns_servers without depending on the resolver resource."
  value       = local.resolver_ip
}

output "private_dns_zone_ids" {
  description = "Map of zone FQDN -> Private DNS zone resource ID. Consumed by spoke and workload modules for VNet links and private-endpoint zone-group registration."
  value       = { for k, m in module.private_dns_zones : k => m.resource_id }
}

output "private_dns_zone_resource_group_name" {
  description = "Name of the resource group that holds the centrally-managed Private DNS zones (i.e., the hub RG)."
  value       = module.rg.name
}

output "workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace."
  value       = module.workspace.resource.workspace_id
}

output "workspace_resource_id" {
  description = "Full Azure resource ID of the Log Analytics workspace."
  value       = module.workspace.resource_id
}
