# Bidirectional hub <-> spoke peering via the AVM peering submodule.
# create_reverse_peering = true emits both halves in a single call. The
# submodule uses azapi only and reaches both subscriptions through the
# parent_id / remote_virtual_network_id ARM IDs — no provider alias needed
# (research.md R-004; verified against
# Azure/terraform-azurerm-avm-res-network-virtualnetwork v0.17.1 peering
# submodule).
#
# Ordering: `use_remote_gateways = true` is rejected by Azure with
# `RemoteVnetHasNoGateways` if the hub VPN gateway hasn't reached
# Succeeded. Tofu's natural dependency graph only sees the hub VNet ID,
# so we add an explicit wait through `wait_for_hub_gateway` keyed on the
# gateway resource ID.
resource "terraform_data" "wait_for_hub_gateway" {
  input = var.hub_vpn_gateway_id
}

module "peering" {
  depends_on = [terraform_data.wait_for_hub_gateway]

  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/peering"
  version = "~> 0.17"

  name                      = "peer-${var.naming_prefix}-${var.spoke_name}-to-hub"
  parent_id                 = module.vnet.resource_id
  remote_virtual_network_id = var.hub_vnet_id

  # Spoke -> Hub forward peering: use the VPN gateway that lives in the hub.
  use_remote_gateways     = true
  allow_forwarded_traffic = false
  allow_gateway_transit   = false

  # Hub -> Spoke reverse peering: hub transits the VPN gateway to the spoke.
  create_reverse_peering          = true
  reverse_name                    = "peer-${var.naming_prefix}-hub-to-${var.spoke_name}"
  reverse_allow_gateway_transit   = true
  reverse_use_remote_gateways     = false
  reverse_allow_forwarded_traffic = false
}
