# Spoke VNet links to each hub-owned Private DNS zone.
#
# Each link is created in the HUB subscription (the zones live there) but
# references the spoke VNet ID. Hence `provider = azurerm.hub`.
#
# Link-conflict handling ("Private DNS zone already linked elsewhere"):
# delegated to the Azure API's natural error response — research.md R-006.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  provider = azurerm.hub

  for_each = var.hub_private_dns_zone_ids

  name                  = "dnsl-${var.naming_prefix}-${var.spoke_name}-${replace(each.key, ".", "-")}"
  resource_group_name   = var.hub_vnet_resource_group_name
  private_dns_zone_name = each.key
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false

  tags = var.tags
}
