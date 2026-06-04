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

  subnets = {
    workload = {
      name           = local.spoke_workload_subnet_name
      address_prefix = var.workload_subnet_prefix
      network_security_group = {
        id = module.nsg.resource_id
      }
    }
  }
}
