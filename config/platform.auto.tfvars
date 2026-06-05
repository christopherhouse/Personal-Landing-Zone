# Platform-level (singleton) configuration.
#
# Shape: see infra/variables.tf "platform" and
#        specs/001-hub-spoke-foundation/data-model.md "Platform entity".
#
# This file holds OPERATOR-EDITED fields only. Discovered fields
# (tenant_id, vpn_access_group_object_id, deployment_app_client_id,
# subscription_slots) are written directly by bootstrap.ps1 into
# bootstrap/outputs/discovered.auto.tfvars.json and auto-loaded by
# tofu — no hand-copy required.

platform = {
  hub_subscription_id     = "f8b910d5-ed06-4f0f-bf36-c8167bba60eb"
  github_repo             = "christopherhouse/Personal-Landing-Zone"
  hub_resource_group_name = "rg-plz-hub-eastus2"
  region                  = "eastus2"
  hub_address_space       = "172.16.0.0/22"
  vpn_client_address_pool = "172.17.0.0/16"
  dns_zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "plz.internal",
  ]
  workspace_retention_days = 30
  naming_prefix            = "plz"
  tags                     = {}
}
