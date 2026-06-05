# Phase 0 Research: Hub-and-Spoke Networking Foundation

**Branch**: `001-hub-spoke-foundation` | **Date**: 2026-06-04

This document captures the technical decisions taken during planning, with rationale and rejected alternatives. Each decision corresponds to a "NEEDS CLARIFICATION" slot that was resolved during Phase 0 — the result is that `plan.md`'s Technical Context contains no remaining `NEEDS CLARIFICATION` markers.

---

## R-001: IaC tool and provider stack

**Decision**: OpenTofu 1.9+ with `hashicorp/azurerm` ~> 4.20, `Azure/azapi` ~> 2.4, `hashicorp/random` ~> 3.5, and `Azure/modtm` ~> 0.3.

**Rationale**:

- Constitution Principle V mandates OpenTofu and forbids Terraform CLI. AVM Terraform modules use the same HCL surface and consume `azurerm`/`azapi` without modification — OpenTofu is a drop-in.
- `azurerm` v4.x is the only line that supports the storage data-plane OIDC auth path (`use_azuread_auth`) the constitution requires for the backend.
- `azapi` is needed by several AVM resource modules (telemetry, internal `azapi_resource_action` calls).
- `modtm` is the AVM telemetry provider; each AVM module accepts `enable_telemetry = false` so no telemetry is actually emitted, but the provider must still be declared.

**Alternatives considered**:

- *Terraform CLI* — explicitly forbidden by Principle V.
- *Pulumi / Bicep* — would forfeit the AVM ecosystem and force a rewrite of every module choice. Not pursued.

---

## R-002: AVM module inventory and the one native escape hatch

**Decision**: Use the AVM Terraform resource-scope modules listed in `plan.md` for every resource type *except* the P2S VPN gateway. The gateway and its public IP are provisioned with native `azurerm_virtual_network_gateway` and `azurerm_public_ip`.

**Rationale**:

- The AVM resource-scope coverage for everything else is GA (or pre-1.0 but actively maintained, e.g., `avm-res-compute-virtualmachine` 0.20.0, `avm-res-network-dnsresolver` 0.8.0) and meets Constitution Principle I's preference.
- The dedicated VPN-gateway pattern module `Azure/avm-ptn-vnetgateway` was archived by the AVM team in October 2025.
- Its successor `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet` (v0.17.1, GA) is the live module but is opinionated for the Azure Landing Zone CAF reference: it provisions Azure Firewall, Bastion, and DDoS Standard by default and forces a connectivity-subscription shape. Using it would directly violate Constitution Principle II.
- A resource-scope `avm-res-network-virtualnetworkgateway` is in "proposed" status and not GA; waiting blocks delivery.
- Native `azurerm_virtual_network_gateway` is well-supported by `azurerm` 4.20 and gives precise control over the SKU floor and the Entra/OpenVPN configuration block.

**Alternatives considered**:

- *Adopt the ALZ pattern module* — rejected (Principle II cost violation; forces Firewall + Bastion + DDoS).
- *Fork or vendor the archived `avm-ptn-vnetgateway`* — rejected (no upstream maintenance, security drift risk).
- *Wait for the resource-scope AVM* — rejected (open-ended timeline; the AVM index has no committed GA date).

The Complexity Tracking entry in `plan.md` records this as the single declared exception to Principle I, with a re-evaluation trigger ("when `avm-res-network-virtualnetworkgateway` reaches GA").

---

## R-003: Multi-subscription provider pattern (static slot aliases)

**Decision**: Pre-declare one `provider "azurerm"` block per subscription in `infra/providers.tf`, each with an `alias` of the form `sub_<slot_name>` (e.g., `sub_hub`, `sub_demo_a`, `sub_demo_b`). The spoke configuration entry references the slot name by string; the `module "spoke"` invocation passes the matching aliased provider through `providers = { azurerm = azurerm.sub_<slot> }`. Adding a spoke in an *existing* subscription is a pure configuration edit. Adding a spoke in a *new* subscription is a one-time HCL edit (one alias block + one entry in `subscriptions.auto.tfvars`).

**Rationale**:

- Terraform/OpenTofu cannot generate `provider` aliases from `for_each`. This is a long-standing language constraint (hashicorp/terraform#30461).
- Static slot aliases are the production-grade pattern used by `Azure/terraform-azurerm-caf-enterprise-scale` and `terraform-azurerm-modules/terraform-azurerm-lznetworking`. They preserve AVM (`azurerm`-based) compatibility.
- The spec's hard requirement is that adding a *spoke* is configuration-only (FR-008, FR-009). Adding a new *subscription* is a meta-event and the spec is silent on whether it must be touch-free; the operator has agreed (in `/speckit-clarify` Q2 + Q3 session) that a one-time HCL edit per new sub is acceptable.

**Alternatives considered**:

- *Code-generate provider aliases pre-`tofu plan` (Terragrunt-style)* — true zero-HCL-edit, but adds an opaque pre-step that hurts debuggability and forces Terragrunt or a custom generator. Rejected for personal-lab scope; revisit if the slot count grows.
- *Use `azapi` exclusively for cross-sub resources* (azapi supports `subscription_id` on each resource) — forfeits AVM modules entirely. Rejected per Principle I.
- *State-per-spoke (separate root + remote state per spoke)* — clean multi-sub story but violates the spec's implicit "single state, single pipeline" model (FR-019 / FR-020). Rejected.
- *Use the `avm-ptn-alz-sub-vending` module* — heavyweight; built for greenfield ALZ rollouts with management-group scope; overkill for a personal lab.

**Operational consequence**: `infra/providers.tf` is the only file that must change when adding a brand-new subscription. The `bootstrap.ps1` step that enumerates subscriptions via `az account list` is the source of truth for which slot names exist; the operator wires a new slot block by copying an existing one when bootstrap adds a sub.

---

## R-004: Cross-subscription peering and Private DNS VNet links

**Decision**:

- **Peering**: Use the AVM peering submodule `Azure/avm-res-network-virtualnetwork/azurerm//modules/peering` with `create_reverse_peering = true`, passing both the hub-side and spoke-side aliased providers via `configuration_aliases`. This emits both halves of the peering in a single call. Hub side: `allow_gateway_transit = true`; spoke side: `use_remote_gateways = true`.
- **Private DNS VNet link**: Use the AVM private DNS zone module's `virtual_network_links` map input. Each entry in the map carries a full VNet resource ID; the resource ID may target any subscription. The link itself is created in the hub subscription (where the zone lives); the deploying identity needs Network Contributor (or equivalent `Microsoft.Network/virtualNetworks/join/action`) in the spoke sub, which the bootstrap Contributor + UAA assignment already covers.

**Rationale**:

- Cross-subscription VNet peering and cross-subscription Private DNS VNet links are both first-class Azure capabilities (confirmed in Microsoft's Private DNS FAQ and the cross-subscription VNet peering doc). The two-half peering pattern + AVM peering submodule is the simplest expression in Terraform.
- `allow_gateway_transit` + `use_remote_gateways` is the documented mechanism for spoke-to-VPN-via-hub traffic and works across subscriptions.

**Alternatives considered**:

- *Hand-rolled `azurerm_virtual_network_peering` resources* — workable but duplicates what the AVM submodule already encapsulates; rejected for consistency with Principle I.
- *Single-side peering (gateway transit only one direction)* — broken by Azure's bidirectional peering semantics; not a real option.

---

## R-005: P2S VPN gateway configuration

**Decision**: Native `azurerm_virtual_network_gateway` with:

- `type = "Vpn"`, `vpn_type = "RouteBased"`
- `sku = "VpnGw2"` (smallest SKU still accepted by `azurerm` 4.x — see "Update 2026-06" below)
- `vpn_client_configuration`:
  - `address_space = [var.vpn_client_address_pool]` (default `10.255.0.0/16`)
  - `vpn_client_protocols = ["OpenVPN"]`
  - `aad_tenant = "https://login.microsoftonline.com/<tenant_id>/"` (trailing slash required by the API)
  - `aad_audience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"` (the **Microsoft-registered Azure VPN Client** application ID — the modern path, supersedes the manually-registered audience values)
  - `aad_issuer = "https://sts.windows.net/<tenant_id>/"`
- A standalone `azurerm_public_ip` (Standard SKU, static allocation) as the gateway IP.
- A separate `GatewaySubnet` carved from the hub VNet (`/27` minimum for VpnGw1; we will use `/27`).

**Rationale**:

- Confirmed by Microsoft Learn (`learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-gateway`) that Entra-auth P2S requires the OpenVPN tunnel type and forbids the Basic SKU.
- The Microsoft-registered audience value is the recommended replacement for the manually-registered Azure VPN Client app and is the only audience supported on Linux Azure VPN client builds.
- VpnGw1 is the cheapest non-Basic SKU and supports up to 250 P2S OpenVPN connections — well above personal-lab needs.

**Alternatives considered**:

- *Basic SKU* — does not support OpenVPN; ruled out.
- *VpnGw1* — original choice, retired from azurerm 4.x's accepted-SKU validation list. The first apply attempt failed with `expected sku to be one of ["VpnGw2" "VpnGw3" "VpnGw4" "VpnGw5" ...], got VpnGw1`.
- *VpnGw2AZ* (zone-redundant variant) — ~25% more expensive for zone redundancy that has no value in a personal lab. Rejected per Principle II.
- *Manually-registered Azure VPN Client app* (audience values from the `openvpn-azure-ad-tenant` doc) — works on Windows/macOS but not on Linux Azure VPN client; rejected for forward compatibility.

**Update 2026-06**: Originally pinned to VpnGw1 as the minimum non-Basic SKU. azurerm 4.x rejects VpnGw1 at provider-validation time; only VpnGw2+ (and their AZ variants) pass. Bumped to VpnGw2. Cost ceiling in `plan.md` raised from $350 to $400/month idle to absorb the ~$71/month delta (VpnGw1 ≈ $140 → VpnGw2 ≈ $211).

---

## R-006: DNS architecture (Private Resolver + Private DNS zones + VPN profile DNS)

**Decision**:

- Hub VNet contains a dedicated `/28` subnet delegated to `Microsoft.Network/dnsResolvers`, hosting one DNS Private Resolver **inbound endpoint** (no outbound endpoint, no forwarding ruleset).
- The inbound endpoint's IP is the 5th IP in its subnet (Azure dynamic allocation default). With the default hub plan (`10.0.0.0/22`) we place the resolver subnet at `10.0.3.0/28` so the resolver IP is `10.0.3.4`.
- Hub owns the full set of centrally managed private DNS zones. Initial zones:
  - `privatelink.blob.core.windows.net` (validation workload's storage PE)
  - `privatelink.vaultcore.azure.net` (reserved for future Key Vault demos; cheap to provision)
  - A custom zone `plz.internal` for any future named records (operator may rename in `platform.auto.tfvars`)
- Every spoke VNet is linked to every centrally-managed zone (no per-spoke opt-in; the cost of zone links is zero and the simplicity benefit dominates).
- The VPN client profile (rendered into the gateway's `vpn_client_configuration`) advertises the inbound endpoint IP as the client DNS server, and advertises hub + spoke CIDRs as the only routed prefixes (split-tunnel; FR-007a).

**Rationale**:

- The inbound endpoint resolves any zone *linked to the VNet the endpoint lives in*. Linking every zone to the hub VNet means the inbound endpoint can resolve all of them — and the VPN client's DNS query reaches the inbound endpoint over the tunnel.
- An outbound endpoint and forwarding ruleset are only needed when DNS must be conditionally forwarded to *external* servers (on-prem, multi-cloud). The spec has no such requirement.
- Linking every spoke to every hub zone is operationally cheaper than asking the spoke config entry to enumerate which zones to link; FR-004a / FR-008's "no extra knobs" goal is preserved.

**Alternatives considered**:

- *Per-spoke zone link opt-in* — adds a config knob with no real-world benefit. Rejected for simplicity.
- *Push DNS server settings on each spoke VNet (`dns_servers = [resolver_ip]`)* — duplicative; VMs in spokes that aren't going through the VPN don't need it (they use Azure-provided 168.63.129.16, which already resolves linked zones via the auto-link path). The VPN profile push is sufficient for the documented user journey.

**Link-conflict handling** (spec.md Edge Cases — "Private DNS zone already linked elsewhere"): no explicit pre-check is implemented. `azurerm_private_dns_zone_virtual_network_link` fails at apply time on conflict, surfacing the conflict as an Azure-side error before the link is created. This is a deliberate "delegate to the Azure API's natural error response" decision rather than an oversight — pre-check logic would have to read the link state across every linked VNet for every zone on every plan, with no actionable improvement over the API's behavior. The pipeline's failure-loud-and-early posture (FR-018, FR-019) makes the Azure-side error visible to the operator in the apply log.

---

## R-007: NSG default posture (trust the VPN pool)

**Decision**: Each spoke gets one platform-managed NSG associated with its workload subnet, with exactly one inbound `Allow` rule for `Source = <vpn_client_address_pool>`, `Protocol = *`, `Source/Destination Port = *`, plus the default deny-all. Hub subnets (GatewaySubnet excluded — Azure manages it) follow the same model where applicable. The `AzureDnsResolver` subnet does not require an NSG (Azure prohibits NSGs on delegated subnets in some configurations and the inbound endpoint is only reachable from VNet-linked sources by design).

**Rationale**: Direct implementation of the clarification answer to Q2 — "trust the VPN pool".

**Alternatives considered**:

- *Service-port allow-list (22/3389/443)* — rejected in clarify session (operator-chosen).
- *No NSGs at all* — would leave subnets with Azure's default intra-VNet allow + internet-deny; works at the limit (no public IPs) but loses an audit trail and lets cross-spoke or hub-to-spoke traffic flow unconstrained, which the operator may later regret.

---

## R-008: Validation workload composition

**Decision**: One `Standard_B1s` Linux VM (Ubuntu 22.04 LTS, generation 2) plus one Storage account with a private endpoint to the blob service. Both live in the `validation` spoke's RG.

- VM:
  - `disable_password_authentication = true`
  - SSH key required by `azurerm_linux_virtual_machine`; deploy a one-time, throwaway key locally only — no key written to state or repo; the VM is *not* expected to be reached by SSH key. Real access is via `az ssh vm` with Entra (FR-016a). The SSH key argument is a workaround for the resource's required field.
  - `extensions` map includes `AADSSHLoginForLinux` (publisher `Microsoft.Azure.ActiveDirectory`, type `AADSSHLoginForLinux`, version `1.0`).
  - System-assigned managed identity enabled (required by the AAD login extension).
  - Role assignment: `Virtual Machine User Login` on the VM scope to the VPN access group (so any VPN-authorized user can also SSH).
- Storage account:
  - `shared_access_key_enabled = false`, `default_to_oauth_authentication = true`.
  - `public_network_access_enabled = false`.
  - Inline `private_endpoints = { blob = { ... } }` on the storage AVM, which auto-creates the PE, the zone group, and registers the A record in `privatelink.blob.core.windows.net`.
  - Role assignment: `Storage Blob Data Reader` on the storage account to the operator's Entra user (or VPN access group) so `az storage blob list` works after VPN connect.

**Rationale**:

- The B1s VM exercises raw L3 connectivity (SSH over VPN) and DNS for VM-auto-registered records.
- The storage PE exercises Azure Private Link DNS auto-registration — the exact pattern future demos will use.
- The `azurerm_linux_virtual_machine` resource (used internally by the compute AVM) requires *some* SSH key. We supply a throwaway public key whose private half is never stored. Real interactive access is via Entra/`az ssh vm`.

**Alternatives considered**:

- *VM only* — wouldn't validate Private Link DNS.
- *Storage PE only* — wouldn't validate raw L3 / SSH.
- *Larger VM SKU* — unjustified cost.

---

## R-009: State backend with OIDC

**Decision**: `azurerm` backend block with `use_oidc = true`, `use_azuread_auth = true`. The state account's subscription, RG, account name, container name, and blob key are supplied at `tofu init` time via `-backend-config=` arguments. The GitHub Actions workflow sets `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID` (the *default* sub for `azurerm` resources — the hub sub).

**Rationale**:

- `use_oidc` plus `use_azuread_auth` is the documented current path for keyless state access. The GH Actions runtime injects `ACTIONS_ID_TOKEN_REQUEST_*` env vars that `azurerm` consumes automatically; nothing else needs to be set.
- Per-state-key rotation is not needed (no secrets exist), so the only sensitive operational concern is RBAC on the state account.

**Alternatives considered**:

- *Workload Identity via `azure/login@v2` with `client-secret`* — violates Principle III.
- *Storage account access keys* — violates Principle III.
- *Pull state ahead of plan and treat it as local* — defeats the audit / single-writer model.

---

## R-010: Bootstrap script (agent-run, idempotent)

**Decision**: `bootstrap/bootstrap.ps1` performs the following, idempotently:

1. Pre-flight: confirm `az` is logged in to the right tenant; refuse to run if `az account get-access-token --tenant <expected>` fails.
2. Enumerate subscriptions: `az account list --query "[?tenantId=='<tenant>']"`. The result becomes the canonical sub slot list.
3. Create the deployment Entra app + service principal if absent. Capture the app's object ID and the SP's object ID.
4. For each `(repo, branch_or_environment)` pair supplied by the operator, create a federated credential on the app via `az ad app federated-credential create`. No client secrets, no certs.
5. Create the VPN access Entra group if absent (display name `sg-plz-vpn-users`). Capture its object ID.
6. For each enumerated subscription, idempotently create role assignments: `Contributor` and `User Access Administrator`, both scoped to `/subscriptions/<id>`, principal = SP object ID.
7. On the state storage account (sub + RG + name supplied as inputs), idempotently create a `Storage Blob Data Contributor` role assignment for the SP at the storage-account scope.
8. Emit two outputs:
   - `bootstrap/outputs/discovered.auto.tfvars.json` — sub slot map keyed by friendly name, plus the VPN access group object ID and SP client ID. Consumed at `tofu plan` time.
   - `bootstrap/outputs/bootstrap-report.md` — a human-readable summary the operator reviews before committing the workflow scoping (repo / branch / env).
9. Re-runs are safe: every step checks current state before mutating.

**Rationale**:

- Encodes the FR-017 / FR-017a flow.
- Uses the operator's interactive `az login` (delegated permissions) so we don't need to give the deployment SP any Microsoft Graph permissions (Principle III + Clarify Q3).
- PowerShell because the operator's environment is Windows; the script avoids any feature requiring PowerShell on macOS/Linux.

**Alternatives considered**:

- *Terraform bootstrap (`azuread` provider) using interactive Entra auth* — adds the `azuread` provider just for setup, complicates the apply path, and forces interactive auth inside a Terraform run that's otherwise SP-authenticated. Rejected.
- *Bicep / ARM template bootstrap* — gratuitous extra tool.

---

## R-011: GitHub Actions workflow shape

**Decision**:

- **`plan.yml`** triggers on `pull_request` against the default branch. Jobs (in order): `fmt-check`, `validate`, `tflint`, `trivy-config`, `plan`. The `plan` job runs `tofu plan -out=tfplan -lock-timeout=5m` and uploads the binary plan file + a human-readable text dump as artifacts. The plan job posts the text dump to the PR as a comment.
- **`apply.yml`** triggers on `push` to the default branch. It downloads the most recent `plan.yml` artifact from the merged PR (or fails if it cannot find one), and runs `tofu apply tfplan`.
- Both workflows declare `permissions: id-token: write, contents: read` (apply also needs `pull-requests: read` to fetch the artifact).
- Both workflows pin OpenTofu via `opentofu/setup-opentofu@v1` with an explicit version.

**Rationale**: Standard plan-on-PR / apply-on-merge pattern that satisfies FR-019 and FR-020 (the apply consumes the PR's plan artifact, not a re-generated plan).

**Alternatives considered**:

- *Apply on every merge re-generating the plan* — racy with concurrent merges; rejected.
- *Manual approval gate before apply* — orthogonal; the operator can add an `environment:` with required reviewers later. Not needed for v1 single-operator lab.

---

## R-012: Cost baseline

**Decision**: Document the steady-state monthly cost in `docs/cost-baseline.md`. Estimated idle figures at writing (USD, eastus2, 2026-06):

| Item | Approx. monthly | Note |
|---|---|---|
| P2S VPN Gateway VpnGw1 | $140 | Cannot be deallocated. |
| DNS Private Resolver inbound endpoint | $130 | One endpoint, ~$0.18/hr × 24 × 30. |
| Log Analytics workspace (idle ingestion) | $0 — $5 | Mostly ingestion-driven; VPN GW + Resolver diagnostics generate minimal volume. |
| Validation VM (B1s, Linux) | $8 | Stoppable; cost target assumes always-on for the validation flow to work on first connect. |
| Validation storage account (LRS, ~1 GB) | $0.02 | Negligible. |
| Validation storage private endpoint | $7.20 | Per PE, per month. |
| Public IP (Standard, gateway) | Included in gateway price | |
| **Estimated idle total** | **~$285 – $290** | Below the $350 ceiling in `plan.md` Constraints. |

**Rationale**: SC-007 requires this be documented and reviewed on every PR that adds an always-on resource.

---

## R-013: Out-of-scope items explicitly named so we don't drift

- Spoke-to-spoke routing (FR-004 second clause).
- Site-to-Site VPN, ExpressRoute, or any on-prem connectivity.
- Multi-region or paired-region replication.
- NSG flow logs, Network Watcher, or in-VNet packet capture.
- Azure Bastion (Clarify Q1 explicitly rejected this path).
- Azure Firewall, Application Gateway / WAF.
- DDoS Protection Standard.
- Cross-tenant or guest-account access.
