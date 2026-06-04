resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

locals {
  storage_account_name       = "st${var.naming_prefix}val${random_string.storage_suffix.result}"
  blob_private_endpoint_name = "pe-${var.naming_prefix}-validation-blob"
}

# Secretless storage account: no shared keys, OAuth-only data plane,
# public network access disabled, single private endpoint to blob with the
# A record auto-registered in the hub-owned privatelink zone (R-006, R-008).
module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.7"

  name      = local.storage_account_name
  location  = var.region
  parent_id = var.target_resource_group_id

  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = false
  min_tls_version                 = "TLS1_2"

  enable_telemetry = false
  tags             = var.tags

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  private_endpoints = {
    blob = {
      name                          = local.blob_private_endpoint_name
      subnet_resource_id            = var.target_subnet_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [var.target_private_dns_zone_id_blob]
    }
  }

  containers = {
    validation = {
      name = "validation"
    }
  }
}
