locals {
  spoke_vnet_name            = "vnet-${var.naming_prefix}-spoke-${var.spoke_name}"
  spoke_workload_subnet_name = "snet-${var.naming_prefix}-spoke-${var.spoke_name}-workload"
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.17"

  name             = local.spoke_vnet_name
  location         = var.region
  parent_id        = module.rg.resource_id
  address_space    = [var.address_space]
  enable_telemetry = false
  tags             = var.tags

  # Spoke VMs/PaaS get the hub-resolver IP via Azure-provided DHCP. They
  # resolve `*.privatelink.*` and `plz.internal` through the resolver
  # without any host-side config.
  dns_servers = {
    dns_servers = [var.hub_resolver_ip]
  }

  subnets = {
    workload = {
      name           = local.spoke_workload_subnet_name
      address_prefix = var.workload_subnet_prefix
      network_security_group = {
        id = module.nsg.resource_id
      }
      nat_gateway = {
        id = azurerm_nat_gateway.this.id
      }
    }
  }
}
