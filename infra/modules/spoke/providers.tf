# Provider requirements for the spoke module.
#
# The default `azurerm` provider is routed to the spoke's subscription by the
# root composition (main.tf passes `providers = { azurerm = azurerm.sub_<slot>, azurerm.hub = azurerm.sub_hub }`).
# The aliased `azurerm.hub` provider is required because Private DNS zone <->
# spoke VNet links are created in the hub subscription (where the zones live)
# even though they reference a spoke-side VNet ID (research.md R-004).
#
# The peering submodule uses azapi only and reaches both subs via parent_id +
# remote_virtual_network_id; it does not need a provider alias passed.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.20"
      configuration_aliases = [azurerm.hub]
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
  }
}
