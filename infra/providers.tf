# Multi-subscription provider model.
#
# Every subscription "slot" declared in config/subscriptions.auto.tfvars must
# have a matching `provider "azurerm" { alias = "sub_<slot_name>" }` block in
# this file. OpenTofu cannot generate provider aliases via for_each (a long-
# standing language constraint), so adding a brand-new subscription requires a
# one-time HCL edit here. See specs/001-hub-spoke-foundation/research.md R-003.
#
# To add a new subscription slot named e.g. "demo_a":
#   1. Add { demo_a = { subscription_id = "<guid>" } } to
#      config/subscriptions.auto.tfvars (or have bootstrap.ps1 emit it).
#   2. Copy the `sub_hub` provider block below.
#   3. Rename `alias = "sub_hub"` → `alias = "sub_demo_a"`.
#   4. Change `subscription_id = var.subscription_slots["hub"].subscription_id`
#      → `var.subscription_slots["demo_a"].subscription_id`.
#   5. Commit. The new slot is now usable from config/spokes.auto.tfvars.

# Default provider — used by root-level resources that don't belong to any
# specific spoke (currently none; the hub module receives its provider through
# `providers = { azurerm = azurerm.sub_hub }` in main.tf). Pointed at the hub
# subscription as a safe default so any accidental root-level resource lands
# somewhere predictable.
provider "azurerm" {
  features {}

  subscription_id     = var.subscription_slots["hub"].subscription_id
  use_oidc            = true
  use_azuread_auth    = true
  storage_use_azuread = true
}

provider "azurerm" {
  alias = "sub_hub"
  features {}

  subscription_id     = var.subscription_slots["hub"].subscription_id
  use_oidc            = true
  use_azuread_auth    = true
  storage_use_azuread = true
}
