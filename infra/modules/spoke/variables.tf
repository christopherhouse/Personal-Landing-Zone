# Spoke module inputs. One module instance per entry in var.spokes.

variable "spoke_name" {
  description = "Logical spoke name (map key from var.spokes). Used in derived resource names."
  type        = string
}

variable "resource_group_name" {
  description = "Spoke resource group name. Created by this module; must NOT pre-exist in the target subscription."
  type        = string
}

variable "region" {
  description = "Azure region for every spoke resource."
  type        = string
}

variable "address_space" {
  description = "Spoke VNet CIDR. Validated for non-overlap in root locals.tf."
  type        = string
}

variable "workload_subnet_prefix" {
  description = "CIDR for the spoke's single workload subnet. Must be a strict subset of address_space."
  type        = string
}

variable "naming_prefix" {
  description = "Prefix for derived resource names (inherited from platform.naming_prefix)."
  type        = string
}

variable "hub_vnet_id" {
  description = "Full ARM ID of the hub VNet. Used by the peering submodule as the remote VNet."
  type        = string
}

variable "hub_vnet_resource_group_name" {
  description = "Hub VNet's resource group name. Surfaced so the spoke module can resolve cross-sub provider routing for DNS zone links."
  type        = string
}

variable "hub_private_dns_zone_ids" {
  description = "Map of zone FQDN -> Private DNS zone resource ID, exported by the hub module. Each zone is linked to this spoke's VNet."
  type        = map(string)
}

variable "vpn_client_address_pool" {
  description = "VPN client CIDR (inherited from platform.vpn_client_address_pool). Source prefix on the NSG's single allow rule."
  type        = string
}

variable "tags" {
  description = "Tags applied to every spoke resource."
  type        = map(string)
  default     = {}
}
