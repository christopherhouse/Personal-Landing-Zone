# Root composition.
#
# - module "hub" runs against the hub subscription via `azurerm.sub_hub`.
# - One `module "spoke_<slot>"` block per declared subscription slot, each
#   `for_each`-filtering var.spokes to entries that target that slot. This
#   is the static-alias-per-slot workaround for OpenTofu's lack of dynamic
#   provider selection in for_each (research.md R-003).
# - module "validation_workload" runs in the spoke that has
#   include_validation_workload = true. For the Phase 3 MVP that spoke MUST
#   be in the `hub` slot; when adding the validation workload to a spoke in
#   a different slot, update the providers + outputs lookup accordingly.
#
# Adding a new subscription slot is a one-time HCL edit: copy `module "spoke_hub"`
# below, rename to `module "spoke_<newslot>"`, point its providers at the new
# alias pair, and the configuration-only "add a spoke" flow extends to that
# slot.

locals {
  # The spoke entry that hosts the validation workload (at most one — enforced
  # in locals.tf by assert_at_most_one_validation_workload). locals.tf already
  # exposes `validation_workload_spokes` as the list of keys; here we need the
  # full spoke object so we can resolve its subscription_slot.
  validation_workload_spoke_entries = {
    for k, s in var.spokes :
    k => s if try(s.include_validation_workload, false)
  }
}

module "hub" {
  source = "./modules/hub"

  providers = {
    azurerm = azurerm.sub_hub
  }

  subscription_id            = var.subscription_slots["hub"].subscription_id
  tenant_id                  = var.platform.tenant_id
  resource_group_name        = var.platform.hub_resource_group_name
  region                     = var.platform.region
  address_space              = var.platform.hub_address_space
  dns_zones                  = var.platform.dns_zones
  workspace_retention_days   = var.platform.workspace_retention_days
  naming_prefix              = var.platform.naming_prefix
  vpn_client_address_pool    = var.platform.vpn_client_address_pool
  vpn_access_group_object_id = var.platform.vpn_access_group_object_id
  tags                       = var.platform.tags
}

# One spoke-module block per slot. The `for_each` filter on var.spokes means
# the block is a no-op when no spoke targets that slot.

module "spoke_hub" {
  source = "./modules/spoke"

  for_each = {
    for k, s in var.spokes :
    k => s if s.subscription_slot == "hub"
  }

  providers = {
    azurerm     = azurerm.sub_hub
    azurerm.hub = azurerm.sub_hub
  }

  spoke_name                   = each.key
  resource_group_name          = each.value.resource_group_name
  region                       = var.platform.region
  address_space                = each.value.address_space
  workload_subnet_prefix       = each.value.workload_subnet_prefix
  naming_prefix                = var.platform.naming_prefix
  hub_vnet_id                  = module.hub.vnet_id
  hub_vnet_resource_group_name = module.hub.private_dns_zone_resource_group_name
  hub_private_dns_zone_ids     = module.hub.private_dns_zone_ids
  vpn_client_address_pool      = var.platform.vpn_client_address_pool
  tags                         = merge(var.platform.tags, try(each.value.tags, {}))
}

# Validation workload — at most one instance. For the Phase 3 MVP, the
# include_validation_workload = true spoke MUST live in the `hub` slot.
module "validation_workload" {
  source = "./modules/workloads/validation"

  for_each = local.validation_workload_spoke_entries

  providers = {
    azurerm = azurerm.sub_hub
  }

  target_resource_group_name      = module.spoke_hub[each.key].resource_group_name
  target_resource_group_id        = "/subscriptions/${var.subscription_slots[each.value.subscription_slot].subscription_id}/resourceGroups/${module.spoke_hub[each.key].resource_group_name}"
  target_subnet_id                = module.spoke_hub[each.key].workload_subnet_id
  target_private_dns_zone_id_blob = module.hub.private_dns_zone_ids["privatelink.blob.core.windows.net"]
  vpn_access_group_object_id      = var.platform.vpn_access_group_object_id
  region                          = var.platform.region
  naming_prefix                   = var.platform.naming_prefix
  tags                            = var.platform.tags
}
