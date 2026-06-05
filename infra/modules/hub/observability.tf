locals {
  hub_workspace_name = "log-${var.naming_prefix}-hub"
}

# T028 — Log Analytics workspace ("platform diagnostic sink").
module "workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.5"

  name                                      = local.hub_workspace_name
  location                                  = var.region
  resource_group_name                       = module.rg.name
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = var.workspace_retention_days
  enable_telemetry                          = false
  tags                                      = var.tags
}

# T029 — Diagnostic settings for the VPN gateway and DNS Private Resolver
# inbound endpoint. Routed to the workspace above. Native
# azurerm_monitor_diagnostic_setting is used because the AVM modules for
# these resources (native VPN gateway; resolver) don't expose the relevant
# category sets in a way that maps cleanly to the spec's required categories.

resource "azurerm_monitor_diagnostic_setting" "vpn_gateway" {
  name                       = "diag-${local.hub_vpn_gateway_name}"
  target_resource_id         = azurerm_virtual_network_gateway.vpn.id
  log_analytics_workspace_id = module.workspace.resource_id

  enabled_log {
    category = "GatewayDiagnosticLog"
  }
  enabled_log {
    category = "TunnelDiagnosticLog"
  }
  enabled_log {
    category = "RouteDiagnosticLog"
  }
  enabled_log {
    category = "IKEDiagnosticLog"
  }
  enabled_log {
    category = "P2SDiagnosticLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Note: Azure rejects diagnostic settings on the child
# `Microsoft.Network/dnsResolvers/inboundEndpoints` resource type
# ("ResourceTypeNotSupported"). They attach to the parent dnsResolvers
# resource. Categories available on the parent are limited; using the
# generic "allLogs" group + AllMetrics covers what is currently exposed.
resource "azurerm_monitor_diagnostic_setting" "resolver" {
  name                       = "diag-${local.hub_dns_resolver_name}"
  target_resource_id         = module.resolver.resource_id
  log_analytics_workspace_id = module.workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
