locals {
  hub_vnet_name = "vnet-${var.naming_prefix}-hub"

  # Derived subnet CIDRs (assumes var.address_space is a /22; data-model.md "Hub-resourced derived entities"):
  #   GatewaySubnet            -> /27 at offset 24 (172.16.3.0/27 within 172.16.0.0/22)
  #   AzureDnsResolverInbound  -> /28 at offset 50 (172.16.3.32/28 within 172.16.0.0/22)
  #   snet-<prefix>-hub-reserve -> /24 at offset 0 (172.16.0.0/24)
  gateway_subnet_cidr  = cidrsubnet(var.address_space, 5, 24)
  resolver_subnet_cidr = cidrsubnet(var.address_space, 6, 50)
  reserve_subnet_cidr  = cidrsubnet(var.address_space, 2, 0)

  reserve_subnet_name  = "snet-${var.naming_prefix}-hub-reserve"
  resolver_subnet_name = "AzureDnsResolverInbound"
  gateway_subnet_name  = "GatewaySubnet"
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.17"

  name             = local.hub_vnet_name
  location         = var.region
  parent_id        = module.rg.resource_id
  address_space    = [var.address_space]
  enable_telemetry = false
  tags             = var.tags

  subnets = {
    gateway = {
      name           = local.gateway_subnet_name
      address_prefix = local.gateway_subnet_cidr
    }
    resolver = {
      name           = local.resolver_subnet_name
      address_prefix = local.resolver_subnet_cidr
      delegations = [
        {
          name = "Microsoft.Network.dnsResolvers"
          service_delegation = {
            name = "Microsoft.Network/dnsResolvers"
          }
        }
      ]
    }
    reserve = {
      name           = local.reserve_subnet_name
      address_prefix = local.reserve_subnet_cidr
    }
  }
}
