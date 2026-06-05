# Per-spoke NAT Gateway for outbound internet from the workload subnet.
#
# Azure retired default outbound access for new VNets on 2025-09-30; spoke
# VMs would otherwise have no path to public registries (apt repos,
# packages.microsoft.com). One NAT Gateway per spoke keeps blast radius
# scoped and lets the operator delete it later (per-spoke) if a particular
# spoke doesn't need outbound.
#
# Sized at the floor: Standard SKU NAT Gateway + one Standard Static PIP,
# zone-redundant (all 3 zones) for cross-AZ availability.
# Idle cost ~$33/spoke/month. Documented in plan.md constraints.

locals {
  spoke_nat_pip_name     = "pip-${var.naming_prefix}-spoke-${var.spoke_name}-nat"
  spoke_nat_gateway_name = "nat-${var.naming_prefix}-spoke-${var.spoke_name}"
}

resource "azurerm_public_ip" "nat" {
  name                = local.spoke_nat_pip_name
  location            = var.region
  resource_group_name = module.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = local.spoke_nat_gateway_name
  location            = var.region
  resource_group_name = module.rg.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}
