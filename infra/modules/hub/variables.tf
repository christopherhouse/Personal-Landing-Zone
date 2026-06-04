# Hub module inputs.
#
# Surfaces every Platform-entity knob the hub needs to provision the hub RG,
# hub VNet (with GatewaySubnet, AzureDnsResolverInbound, and a reserve subnet),
# the P2S VPN gateway + public IP, the DNS Private Resolver inbound endpoint,
# the Private DNS zones, and the Log Analytics workspace + diagnostic settings.
#
# Shape sourced from specs/001-hub-spoke-foundation/data-model.md "Platform entity".

variable "subscription_id" {
  description = "Hub subscription ID. Surfaced for diagnostics/labels; the provider alias supplies the actual auth context."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID. Used in vpn_client_configuration aad_tenant / aad_issuer URLs."
  type        = string
}

variable "resource_group_name" {
  description = "Hub resource group name. Created by this module; must NOT pre-exist."
  type        = string
}

variable "region" {
  description = "Azure region for every hub resource."
  type        = string
}

variable "address_space" {
  description = "Hub VNet CIDR (>= /22 recommended). Subdivided into GatewaySubnet (/27), AzureDnsResolverInbound (/28), and a /24 reserve."
  type        = string
}

variable "dns_zones" {
  description = "Private DNS zone FQDNs to provision in the hub RG and link to the hub VNet."
  type        = list(string)
}

variable "workspace_retention_days" {
  description = "Log Analytics workspace retention in days. 30-730 per Azure API."
  type        = number
  default     = 30
}

variable "naming_prefix" {
  description = "Prefix for derived resource names (e.g., 'plz' -> vnet-plz-hub)."
  type        = string
}

variable "vpn_client_address_pool" {
  description = "CIDR carved out for P2S VPN client allocations. Pushed into the gateway's vpn_client_configuration.address_space."
  type        = string
}

variable "vpn_access_group_object_id" {
  description = "Object ID of the Entra group whose members may connect to the P2S VPN. Surfaced for downstream RBAC; not consumed inside this module."
  type        = string
}

variable "tags" {
  description = "Tags applied to every hub resource."
  type        = map(string)
  default     = {}
}
