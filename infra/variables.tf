# Top-level variables for the Hub-and-Spoke Networking Foundation root.
#
# Shape and semantics are defined in:
#   specs/001-hub-spoke-foundation/data-model.md
#   specs/001-hub-spoke-foundation/contracts/spokes-inventory.schema.md
#   specs/001-hub-spoke-foundation/contracts/subscriptions-inventory.schema.md
#
# Cross-entity invariants (slot consistency, address-space non-overlap,
# subnet containment, name uniqueness, validation-workload singleton) are
# enforced in locals.tf via terraform_data preconditions, because validation {}
# blocks can only reason about a single variable in isolation.

variable "platform" {
  description = <<-EOT
    Singleton platform-level configuration. Sourced from
    config/platform.auto.tfvars (operator-edited fields) plus
    bootstrap/outputs/discovered.auto.tfvars.json (vpn_access_group_object_id,
    tenant_id).
  EOT

  type = object({
    tenant_id                  = string
    hub_subscription_id        = string
    hub_resource_group_name    = string
    region                     = optional(string, "eastus2")
    hub_address_space          = optional(string, "10.0.0.0/22")
    vpn_client_address_pool    = optional(string, "10.255.0.0/16")
    dns_zones                  = optional(list(string), ["privatelink.blob.core.windows.net", "privatelink.vaultcore.azure.net", "plz.internal"])
    workspace_retention_days   = optional(number, 30)
    naming_prefix              = optional(string, "plz")
    github_repo                = string
    vpn_access_group_object_id = string
    tags                       = optional(map(string), {})
  })

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.platform.tenant_id))
    error_message = "platform.tenant_id must be a valid GUID."
  }

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.platform.hub_subscription_id))
    error_message = "platform.hub_subscription_id must be a valid GUID."
  }

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.platform.vpn_access_group_object_id))
    error_message = "platform.vpn_access_group_object_id must be a valid GUID (object ID of the sg-plz-vpn-users Entra group). It is normally populated by bootstrap.ps1 via bootstrap/outputs/discovered.auto.tfvars.json."
  }

  validation {
    condition     = can(regex("^rg-[a-z0-9-]+$", var.platform.hub_resource_group_name))
    error_message = "platform.hub_resource_group_name must match ^rg-[a-z0-9-]+$ (e.g., rg-plz-hub-eastus2)."
  }

  validation {
    condition     = can(cidrnetmask(var.platform.hub_address_space))
    error_message = "platform.hub_address_space must be a valid CIDR (e.g., 10.0.0.0/22)."
  }

  validation {
    condition     = can(cidrnetmask(var.platform.vpn_client_address_pool))
    error_message = "platform.vpn_client_address_pool must be a valid CIDR (e.g., 10.255.0.0/16)."
  }

  validation {
    condition     = length(var.platform.dns_zones) > 0
    error_message = "platform.dns_zones must contain at least one zone."
  }
}

variable "subscription_slots" {
  description = <<-EOT
    Map of subscription "slot" name -> subscription metadata. The key is the
    logical slot name referenced by spoke entries; it must also match the
    suffix of a `provider "azurerm" { alias = "sub_<slot_name>" }` block in
    providers.tf. The "hub" slot is required and must equal
    platform.hub_subscription_id.
  EOT

  type = map(object({
    subscription_id = string
  }))

  validation {
    condition = alltrue([
      for k, _ in var.subscription_slots :
      can(regex("^[a-z][a-z0-9_]*$", k))
    ])
    error_message = "Each subscription_slots key (slot name) must match ^[a-z][a-z0-9_]*$ (lowercase, underscores allowed). Examples: hub, demo_a, demo_b."
  }

  validation {
    condition = alltrue([
      for _, v in var.subscription_slots :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.subscription_id))
    ])
    error_message = "Each subscription_slots[*].subscription_id must be a valid GUID."
  }

  validation {
    condition     = contains(keys(var.subscription_slots), "hub")
    error_message = "subscription_slots must contain a 'hub' entry. (The hub slot's subscription_id must equal platform.hub_subscription_id; cross-checked in locals.tf.)"
  }
}

variable "spokes" {
  description = <<-EOT
    Map of logical spoke name -> spoke configuration. This is the operator's
    primary day-2 interface; the supported way to add a spoke is to edit
    config/spokes.auto.tfvars (and only this file, when the target
    subscription already has a slot declared). See
    contracts/spokes-inventory.schema.md.
  EOT

  type = map(object({
    subscription_slot           = string
    resource_group_name         = string
    address_space               = string
    workload_subnet_prefix      = string
    include_validation_workload = optional(bool, false)
    dns_zone_links              = optional(list(string), null)
    tags                        = optional(map(string), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, _ in var.spokes :
      can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", k))
    ])
    error_message = "Each spoke key (logical name) must match ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ (lowercase, hyphens allowed, 3-40 chars, must start with a letter and end with a letter or digit)."
  }

  validation {
    condition = alltrue([
      for _, v in var.spokes :
      can(regex("^rg-[a-z0-9-]+$", v.resource_group_name))
    ])
    error_message = "Each spoke.resource_group_name must match ^rg-[a-z0-9-]+$."
  }

  validation {
    condition = alltrue([
      for _, v in var.spokes :
      can(cidrnetmask(v.address_space))
    ])
    error_message = "Each spoke.address_space must be a valid CIDR (e.g., 10.1.0.0/22)."
  }

  validation {
    condition = alltrue([
      for _, v in var.spokes :
      can(cidrnetmask(v.workload_subnet_prefix))
    ])
    error_message = "Each spoke.workload_subnet_prefix must be a valid CIDR (e.g., 10.1.0.0/24)."
  }
}
