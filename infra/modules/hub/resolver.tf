locals {
  hub_dns_resolver_name = "dnspr-${var.naming_prefix}-hub"
}

# DNS Private Resolver — inbound endpoint only. No outbound endpoint, no
# forwarding ruleset (research.md R-006). The inbound endpoint resolves any
# zone linked to the hub VNet; spokes reach it over the VPN tunnel via the
# `additional_dns_servers` field on the VPN gateway (gateway.tf T025).
module "resolver" {
  source  = "Azure/avm-res-network-dnsresolver/azurerm"
  version = "~> 0.8"

  name                        = local.hub_dns_resolver_name
  location                    = var.region
  resource_group_name         = module.rg.name
  virtual_network_resource_id = module.vnet.resource_id
  enable_telemetry            = false
  tags                        = var.tags

  inbound_endpoints = {
    primary = {
      name                         = "inbound-primary"
      subnet_name                  = local.resolver_subnet_name
      private_ip_allocation_method = "Static"
      private_ip_address           = local.resolver_ip
    }
  }
}
