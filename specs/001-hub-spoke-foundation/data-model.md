# Phase 1 Data Model: Hub-and-Spoke Networking Foundation

**Branch**: `001-hub-spoke-foundation` | **Date**: 2026-06-04

For an IaC project, the "data model" is the shape of the input variables and the relationships among the entities they describe. Concrete HCL types and validations live in `infra/variables.tf` and `infra/locals.tf`; the contracts that human operators interact with live under [`contracts/`](./contracts/).

## Top-level entity overview

```text
┌──────────────────────────────┐
│ Platform                     │
│ (singleton — described by    │
│ platform.auto.tfvars)        │
│                              │
│  • tenant_id                 │
│  • hub_subscription_id       │
│  • hub_resource_group_name   │
│  • region                    │
│  • hub_address_space (CIDR)  │
│  • vpn_client_address_pool   │
│  • dns_zones (list)          │
│  • workspace_retention_days  │
│  • naming_prefix (e.g. "plz")│
└──────────────┬───────────────┘
               │
               │ 1
               │
               │ owns
               │
               │ N
       ┌───────▼────────┐               ┌──────────────────────────┐
       │ Subscription   │   uses 1..*   │  Spoke                   │
       │ Slot           │◄──────────────┤  (one entry per spoke    │
       │                │               │   in spokes.auto.tfvars) │
       │  • slot_name   │               │                          │
       │  • subscription│               │  • name                  │
       │    _id         │               │  • subscription_slot     │
       │                │               │  • resource_group_name   │
       └────────────────┘               │  • address_space         │
                                        │  • workload_subnet_prefix│
                                        │  • optional flags        │
                                        └────────────┬─────────────┘
                                                     │
                                                     │ 0..1
                                                     │
                                                     │ hosts
                                                     │
                                          ┌──────────▼────────────┐
                                          │ Validation Workload    │
                                          │ (initial spoke only)   │
                                          │                        │
                                          │  • linux_vm            │
                                          │  • storage_account     │
                                          │  • storage_blob_pe     │
                                          └────────────────────────┘
```

Cross-cutting entities owned by the hub:

- **Hub VNet** — single instance.
- **VPN gateway** + its **public IP** — single instance, attached to the hub VNet.
- **DNS Private Resolver inbound endpoint** — single instance.
- **Private DNS zones** — N instances; one Azure-Private-Link zone per service consumed (initial set: `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`), plus the operator-named custom zone (default `plz.internal`).
- **Log Analytics workspace** — single instance ("platform diagnostic sink").
- **VPN access group** — Entra group, *not* an Azure resource; referenced by object ID only.

## Platform entity (singleton)

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `tenant_id` | string (GUID) | Y | — | Single Entra tenant. Validated at plan time. |
| `hub_subscription_id` | string (GUID) | Y | — | One of the slots in `subscriptions.auto.tfvars`. |
| `hub_resource_group_name` | string | Y | — | Created by the platform; must NOT pre-exist. Validation: `^rg-[a-z0-9-]+$`. |
| `region` | string | Y | `eastus2` | Single-region only. |
| `hub_address_space` | string (CIDR) | Y | `10.0.0.0/22` | Subdivided into GatewaySubnet `10.0.3.0/27`, AzureDnsResolverSubnet `10.0.3.32/28`, and a reserve subnet `10.0.0.0/24` for future hub services. |
| `vpn_client_address_pool` | string (CIDR) | Y | `10.255.0.0/16` | Carved from `10.255.0.0/8` to keep separation from the `10.0.0.0/8` spoke pool. Must not overlap with hub or any spoke (FR-011). |
| `dns_zones` | list(string) | Y | `["privatelink.blob.core.windows.net", "privatelink.vaultcore.azure.net", "plz.internal"]` | Operator can extend; every zone is linked to every spoke. |
| `workspace_retention_days` | number | N | `30` | FR-022b minimum. |
| `naming_prefix` | string | N | `plz` | Used in resource names (e.g., `rg-plz-hub-eastus2`, `vnet-plz-hub`). |
| `github_repo` | string | Y | — | `<owner>/<repo>` form. Set during bootstrap; consumed by the apply workflow's environment scoping. |
| `vpn_access_group_object_id` | string (GUID) | Y | — | Discovered by `bootstrap.ps1`; persisted to `bootstrap/outputs/discovered.auto.tfvars.json`. |
| `tags` | map(string) | N | `{}` | Tags applied to every resource the platform creates. |

## Subscription Slot entity

Stored in `subscriptions.auto.tfvars` as a map:

```hcl
subscription_slots = {
  hub    = { subscription_id = "00000000-0000-0000-0000-000000000001" }
  demo_a = { subscription_id = "00000000-0000-0000-0000-000000000002" }
  demo_b = { subscription_id = "00000000-0000-0000-0000-000000000003" }
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `slot_name` (map key) | string | Y | Matches the `provider "azurerm"` alias declared in `infra/providers.tf` (e.g., key `demo_a` ↔ `alias = "sub_demo_a"`). Validation: `^[a-z][a-z0-9_]*$`. |
| `subscription_id` | string (GUID) | Y | Validated at plan time against the operator's enumerated subs. |

**Invariants**:

- The `hub` slot MUST exist and MUST match `platform.hub_subscription_id`.
- Each slot referenced by a spoke entry MUST exist in this map AND MUST have a matching provider alias in `infra/providers.tf` — otherwise plan fails with a clear error from `locals.tf`'s assertion logic.

## Spoke entity

Stored in `spokes.auto.tfvars` as a map keyed by logical spoke name:

```hcl
spokes = {
  validation = {
    subscription_slot     = "hub"
    resource_group_name   = "rg-plz-spoke-validation-eastus2"
    address_space         = "10.1.0.0/22"
    workload_subnet_prefix = "10.1.0.0/24"
    include_validation_workload = true
  }
  # demo_app = {
  #   subscription_slot     = "demo_a"
  #   resource_group_name   = "rg-demo-app-eastus2"
  #   address_space         = "10.2.0.0/22"
  #   workload_subnet_prefix = "10.2.0.0/24"
  # }
}
```

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` (map key) | string | Y | — | Unique across the inventory (FR-012). Validation: `^[a-z][a-z0-9-]{1,38}[a-z0-9]$`. Used in resource names. |
| `subscription_slot` | string | Y | — | Must be a key in `subscription_slots`. |
| `resource_group_name` | string | Y | — | Created by the platform; must NOT pre-exist. Unique across the inventory (FR-012). |
| `address_space` | string (CIDR) | Y | — | `/22` recommended. Must NOT overlap with hub, VPN pool, or any other spoke (FR-011). |
| `workload_subnet_prefix` | string (CIDR) | Y | — | Must be inside `address_space`. |
| `include_validation_workload` | bool | N | `false` | When `true`, the workload submodule deploys the B1s VM + storage PE in this spoke. The initial deployment sets this `true` for the `validation` spoke only. |
| `dns_zone_links` | list(string) | N | All hub zones | Override only if a future spoke explicitly should not be linked to a given zone. Default behavior links every spoke to every hub zone. |
| `tags` | map(string) | N | `{}` | Merged into the inherited platform tags. |

## Cross-entity invariants (enforced in `locals.tf`)

1. **Slot/provider consistency** — every distinct `subscription_slot` referenced by a spoke must have a corresponding provider alias declared in `infra/providers.tf`. If a spoke references a missing slot, plan halts with: `"Spoke '<name>' references unknown subscription slot '<slot>'. Add a provider alias and a subscription_slots entry first."`
2. **Address-space non-overlap** — pairwise check that the hub CIDR, the VPN client pool, and every spoke `address_space` are mutually disjoint. Failure halts plan with the conflicting pair named.
3. **Subnet containment** — every `workload_subnet_prefix` MUST be a strict subset of its spoke's `address_space`.
4. **Name uniqueness** — spoke logical names MUST be unique; spoke `resource_group_name` values MUST be unique.
5. **Validation workload singleton** — at most one spoke may set `include_validation_workload = true`. Multiple instances are rejected at plan time.

## Hub-resourced derived entities (no operator-facing config knob)

| Entity | Source of name | Source of size / SKU |
|---|---|---|
| Hub RG | `var.platform.hub_resource_group_name` | — |
| Hub VNet | `"vnet-${prefix}-hub"` | `var.platform.hub_address_space` |
| GatewaySubnet | Hardcoded `GatewaySubnet` | `/27` slice |
| AzureDnsResolverSubnet | Hardcoded `AzureDnsResolverInbound` | `/28` slice, delegated to `Microsoft.Network/dnsResolvers` |
| Hub reserve subnet | `"snet-${prefix}-hub-reserve"` | `/24` for future hub services |
| VPN gateway public IP | `"pip-${prefix}-vpn"` | Standard, Static |
| VPN gateway | `"vgw-${prefix}-hub"` | `VpnGw1`, Generation 2 |
| DNS Private Resolver | `"dnspr-${prefix}-hub"` | inbound-only |
| Private DNS zones | from `var.platform.dns_zones` | n/a |
| Log Analytics workspace | `"log-${prefix}-hub"` | PerGB2018 tier, `workspace_retention_days` retention |

## Spoke-resourced derived entities

| Entity | Source of name | Notes |
|---|---|---|
| Spoke RG | `var.spokes[k].resource_group_name` | Operator-named. |
| Spoke VNet | `"vnet-${prefix}-spoke-${k}"` | `var.spokes[k].address_space` |
| Workload subnet | `"snet-${prefix}-spoke-${k}-workload"` | `var.spokes[k].workload_subnet_prefix` |
| Workload NSG | `"nsg-${prefix}-spoke-${k}"` | One Allow rule: source `var.platform.vpn_client_address_pool`, dest `*`, port `*`, protocol `*`. |
| Hub↔spoke peering pair | `"peer-${prefix}-hub-to-${k}"` / `"peer-${prefix}-${k}-to-hub"` | Hub side: `allow_gateway_transit = true`. Spoke side: `use_remote_gateways = true`. |
| Spoke ↔ each hub DNS zone link | `"dnsl-${prefix}-${k}-${zone}"` | One per zone; `registration_enabled = false`. |

## Validation workload entities (initial spoke only)

| Entity | Source of name | SKU / config |
|---|---|---|
| Linux VM | `"vm-${prefix}-validation"` | `Standard_B1s`, Ubuntu 22.04 LTS gen 2, system-assigned MI. |
| AAD SSH login extension | n/a (extension on VM) | `Microsoft.Azure.ActiveDirectory/AADSSHLoginForLinux/1.0` |
| Throwaway SSH public key | n/a | Generated locally during bootstrap; private half never persisted. |
| Storage account | `"st${prefix}val${random_suffix}"` | LRS, blob-only, `shared_access_key_enabled = false`, `public_network_access_enabled = false`. |
| Storage blob private endpoint | `"pe-${prefix}-validation-blob"` | Auto-creates A record in `privatelink.blob.core.windows.net`. |
| Role assignment: VPN group → VM | n/a | `Virtual Machine User Login` at VM scope. |
| Role assignment: VPN group → storage | n/a | `Storage Blob Data Reader` at storage account scope. |

## State / lifecycle notes

- The platform is single-environment; there is no `dev`/`prod` overlay. State key: `personal-landing-zone/hub-and-spoke.tfstate`.
- Adding a spoke is purely additive — no module instance referencing other spokes' inputs.
- Removing a spoke entry triggers destroy of the spoke RG and everything inside it; the destroy plan is the operator's final guard rail.
- The validation workload's `include_validation_workload = true` flag should normally remain `true` to preserve User Story 1's end-to-end smoke test. Setting it to `false` after initial validation is allowed (saves the B1s + PE cost) but means future redeploys cannot prove SC-001 without flipping it back on.
