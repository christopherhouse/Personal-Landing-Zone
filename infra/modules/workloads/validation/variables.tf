# Validation workload inputs. The platform deploys at most one instance of
# this module — see locals.tf assert_at_most_one_validation_workload.

variable "target_resource_group_name" {
  description = "Name of the spoke RG into which the validation VM + storage account are placed."
  type        = string
}

variable "target_resource_group_id" {
  description = "Resource ID of the spoke RG (required by storage AVM v0.7's parent_id input)."
  type        = string
}

variable "target_subnet_id" {
  description = "Resource ID of the spoke's workload subnet."
  type        = string
}

variable "target_private_dns_zone_id_blob" {
  description = "Resource ID of the privatelink.blob.core.windows.net zone (lives in the hub RG). Used as the zone-group target for the storage account's blob private endpoint."
  type        = string
}

variable "vpn_access_group_object_id" {
  description = "Object ID of the Entra VPN access group. Granted Virtual Machine User Login on the VM and Storage Blob Data Reader on the storage account."
  type        = string
}

variable "region" {
  description = "Azure region for every workload resource."
  type        = string
}

variable "naming_prefix" {
  description = "Naming prefix (e.g., 'plz') inherited from the platform."
  type        = string
}

variable "tags" {
  description = "Tags applied to every workload resource."
  type        = map(string)
  default     = {}
}
