module "rg" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "~> 0.4"

  name             = var.resource_group_name
  location         = var.region
  tags             = var.tags
  enable_telemetry = false
}
