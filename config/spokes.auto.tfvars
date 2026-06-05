# Spokes inventory — the operator's primary day-2 interface.
#
# Shape: specs/001-hub-spoke-foundation/contracts/spokes-inventory.schema.md
#
# To add a spoke in an EXISTING subscription slot: append an entry to the map
# below, open a PR, merge. To add a spoke in a NEW subscription slot: see
# docs/adding-a-spoke.md (also requires a one-time HCL edit in providers.tf).

spokes = {
  validation = {
    subscription_slot           = "hub"
    resource_group_name         = "rg-plz-spoke-validation-eastus2"
    address_space               = "172.16.4.0/22"
    workload_subnet_prefix      = "172.16.4.0/24"
    include_validation_workload = true
  }
}
