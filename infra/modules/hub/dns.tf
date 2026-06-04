# Private DNS zones — one module instance per zone in var.dns_zones.
# Each zone is linked to the hub VNet itself so the DNS Private Resolver
# inbound endpoint (resolver.tf) can resolve it. Spoke VNets are linked
# separately by the spoke module (spoke/dns-links.tf).
module "private_dns_zones" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "~> 0.5"

  for_each = toset(var.dns_zones)

  domain_name      = each.value
  parent_id        = module.rg.resource_id
  enable_telemetry = false
  tags             = var.tags

  virtual_network_links = {
    hub = {
      name                 = "dnsl-${var.naming_prefix}-hub-${replace(each.value, ".", "-")}"
      virtual_network_id   = module.vnet.resource_id
      registration_enabled = false
    }
  }
}
