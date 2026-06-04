locals {
  spoke_workload_nsg_name = "nsg-${var.naming_prefix}-spoke-${var.spoke_name}"
}

# Per R-007 + T034: one inbound Allow rule for the VPN client pool; everything
# else falls through to Azure's default deny-all.
module "nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "~> 0.5"

  name                = local.spoke_workload_nsg_name
  location            = var.region
  resource_group_name = module.rg.name
  enable_telemetry    = false
  tags                = var.tags

  security_rules = {
    allow_vpn_pool = {
      name                       = "Allow-VpnClientPool-Any"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = var.vpn_client_address_pool
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "*"
    }
  }
}
