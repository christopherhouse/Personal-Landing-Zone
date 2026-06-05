locals {
  hub_vnet_name = "vnet-${var.naming_prefix}-hub"

  # Derived subnet CIDRs (assumes var.address_space is a /22; data-model.md "Hub-resourced derived entities"):
  #   GatewaySubnet            -> /27 at offset 24 (172.16.3.0/27 within 172.16.0.0/22)
  #   AzureDnsResolverInbound  -> /28 at offset 50 (172.16.3.32/28 within 172.16.0.0/22)
  #   snet-<prefix>-hub-reserve -> /24 at offset 0 (172.16.0.0/24)
  gateway_subnet_cidr  = cidrsubnet(var.address_space, 5, 24)
  resolver_subnet_cidr = cidrsubnet(var.address_space, 6, 50)
  reserve_subnet_cidr  = cidrsubnet(var.address_space, 2, 0)

  reserve_subnet_name  = "snet-${var.naming_prefix}-hub-reserve"
  resolver_subnet_name = "AzureDnsResolverInbound"
  gateway_subnet_name  = "GatewaySubnet"

  # Resolver inbound endpoint IP — pinned to the 5th address in the resolver
  # subnet (Azure reserves the first 4 addresses + last for itself, so .36 is
  # the first usable IP in a /28 starting at .32). Computed up-front so:
  #   1. The hub VNet can advertise it via dns_servers without depending on
  #      the resolver resource (would create a cycle: VNet -> resolver ->
  #      resolver_subnet -> VNet).
  #   2. The spoke VNets get a deterministic value through outputs without
  #      needing a refresh after every apply.
  # The resolver is configured with allocation_method = Static and this IP.
  resolver_ip = cidrhost(local.resolver_subnet_cidr, 4)
}

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.17"

  name             = local.hub_vnet_name
  location         = var.region
  parent_id        = module.rg.resource_id
  address_space    = [var.address_space]
  enable_telemetry = false
  tags             = var.tags

  # Advertise the resolver IP as the VNet's DNS server. Every VM/PaaS in the
  # hub VNet that uses Azure-provided DHCP picks this up. Doesn't affect P2S
  # VPN clients (those get DNS from the gateway's vpn_client_configuration,
  # which classic VNet-attached gateways can't push — see quickstart.md
  # Step 1.3 + NRPT workaround).
  dns_servers = {
    dns_servers = [local.resolver_ip]
  }

  subnets = {
    gateway = {
      name           = local.gateway_subnet_name
      address_prefix = local.gateway_subnet_cidr
    }
    resolver = {
      name           = local.resolver_subnet_name
      address_prefix = local.resolver_subnet_cidr
      delegations = [
        {
          name = "Microsoft.Network.dnsResolvers"
          service_delegation = {
            name = "Microsoft.Network/dnsResolvers"
          }
        }
      ]
    }
    reserve = {
      name           = local.reserve_subnet_name
      address_prefix = local.reserve_subnet_cidr
    }
  }
}
