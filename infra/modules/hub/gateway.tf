locals {
  hub_gateway_pip_name = "pip-${var.naming_prefix}-vpn"
  hub_vpn_gateway_name = "vgw-${var.naming_prefix}-hub"

  # Microsoft-registered Azure VPN Client application ID. Modern audience that
  # supersedes the manually-registered values and is the only one supported on
  # Linux Azure VPN client builds (research.md R-005).
  azure_vpn_client_audience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"
}

# T024 — Standard, static public IP for the VPN gateway. Standard SKU required
# by Azure for VpnGw1+ on RouteBased Vpn gateways.
module "gateway_pip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "~> 0.2"

  name                = local.hub_gateway_pip_name
  location            = var.region
  resource_group_name = module.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
  enable_telemetry    = false
  tags                = var.tags
}

# T025 — Native azurerm_virtual_network_gateway. The dedicated AVM module for
# VPN gateways was archived (Constitution escape hatch (c); see plan.md
# Complexity Tracking and research.md R-002 / R-005).
#
# additional_dns_servers pushes the DNS Private Resolver inbound endpoint IP
# (resolver.tf T026) into the VPN client profile so connected clients resolve
# Private DNS via the hub. Satisfies FR-005 / FR-007.
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = local.hub_vpn_gateway_name
  location            = var.region
  resource_group_name = module.rg.name

  type       = "Vpn"
  vpn_type   = "RouteBased"
  sku        = "VpnGw2AZ"
  generation = "Generation2"

  active_active = false
  bgp_enabled   = false

  ip_configuration {
    name                          = "gw-ip-config"
    public_ip_address_id          = module.gateway_pip.resource_id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = module.vnet.subnets["gateway"].resource_id
  }

  vpn_client_configuration {
    address_space        = [var.vpn_client_address_pool]
    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]

    aad_tenant   = "https://login.microsoftonline.com/${var.tenant_id}/"
    aad_audience = local.azure_vpn_client_audience
    aad_issuer   = "https://sts.windows.net/${var.tenant_id}/"

    # NOTE: Pushing the DNS Private Resolver IP to VPN clients is NOT possible
    # via this resource. The classic Microsoft.Network/virtualNetworkGateways
    # REST API has no `customDnsServers` / `dnsServers` property on
    # VpnClientConfiguration; the Azure Portal's "Custom DNS servers" field
    # is rendered into the downloaded VPN client profile at generation time,
    # not persisted to ARM. (`customDnsServers` only exists on the separate
    # Microsoft.Network/p2sVpnGateways vWAN resource.) The resolver IP is
    # surfaced as a root output and the operator injects it into
    # azurevpnconfig.xml once after profile download — see quickstart.md
    # Part 1 step 1.3.
  }

  tags = var.tags
}
