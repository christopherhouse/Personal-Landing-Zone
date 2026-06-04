# Implementation Plan: Hub-and-Spoke Networking Foundation

**Branch**: `001-hub-spoke-foundation` | **Date**: 2026-06-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-hub-spoke-foundation/spec.md`

## Summary

Deploy a persistent Azure hub-and-spoke virtual network that supplies P2S VPN access and centralized private DNS, so future demo workloads can be layered into new spokes by editing a single configuration entry. The hub holds the Entra-authenticated P2S VPN gateway, the Azure DNS Private Resolver inbound endpoint, the Private DNS zones (custom + Azure Private Link), and a small Log Analytics workspace. Each spoke is a peered VNet, optionally living in a different operator subscription, with a workload subnet whose NSG trusts the VPN client pool. The initial deployment includes one validation spoke containing a small Linux VM (Entra SSH login) and a Storage account with a private endpoint, exercising both raw private-IP connectivity and Private Link DNS auto-registration end-to-end. All infrastructure is OpenTofu, all CI/CD authentication is Entra OIDC (no client secrets, no SAS), and adding spokes is a configuration-only change unless a brand-new subscription is introduced (one-time provider alias addition).

## Technical Context

**Language/Version**: OpenTofu 1.9 or later (pinned in `.tool-versions` and the workflow). Terraform CLI is forbidden by the project constitution.

**Primary Dependencies**:

- Providers (pinned in `versions.tf`):
  - `hashicorp/azurerm` ~> 4.20
  - `Azure/azapi` ~> 2.4
  - `hashicorp/random` ~> 3.5
  - `Azure/modtm` ~> 0.3 (AVM telemetry; disabled per-module via `enable_telemetry = false`)
- Azure Verified Modules (Terraform), tag-pinned:
  - `Azure/avm-res-resources-resourcegroup/azurerm` ~> 0.4
  - `Azure/avm-res-network-virtualnetwork/azurerm` ~> 0.17 (plus its `peering` submodule)
  - `Azure/avm-res-network-privatednszone/azurerm` ~> 0.5
  - `Azure/avm-res-network-dnsresolver/azurerm` ~> 0.8
  - `Azure/avm-res-network-networksecuritygroup/azurerm` ~> 0.5
  - `Azure/avm-res-operationalinsights-workspace/azurerm` ~> 0.5
  - `Azure/avm-res-compute-virtualmachine/azurerm` ~> 0.20 (uses the `extensions` input for AADSSHLoginForLinux)
  - `Azure/avm-res-storage-storageaccount/azurerm` ~> 0.7 (uses inline `private_endpoints`)
- Native `azurerm` resources used directly:
  - `azurerm_virtual_network_gateway` + `azurerm_public_ip` for the P2S VPN gateway — see Constitution Check below for AVM-first justification.
  - `azurerm_role_assignment` for arbitrary scope/principal pairs (e.g., `Virtual Machine User Login` on the validation VM, `Storage Blob Data Reader` on the storage PE, etc.). Inline `role_assignments` maps on individual AVM modules are used wherever the assignment is local to that module.

**Storage**: Pre-existing Azure Storage account holding the OpenTofu state. Backend = `azurerm` with `use_oidc = true` and `use_azuread_auth = true` (no storage keys, no SAS). Coordinates (state subscription ID, RG, account, container) supplied at bootstrap and consumed by the workflow as `-backend-config=` arguments and `ARM_*` env vars.

**Testing**: This project ships no application code, so "testing" is layered:

1. Static analysis on every PR: `tofu fmt -check`, `tofu validate`, `tflint` with the `azurerm` ruleset, `trivy config` (or `checkov`).
2. `tofu plan` on every PR with the plan artifact uploaded; reviewer reads the diff before merging.
3. End-to-end validation via the manual procedure in [quickstart.md](./quickstart.md) — VPN connect, `nslookup` of the storage PE, `az ssh vm` to the validation VM, file copy through the private endpoint. This is the authoritative acceptance test for User Story 1.

**Target Platform**: Microsoft Azure, multi-subscription within a single Entra tenant, single Azure region (operator-supplied; default `eastus2`).

**Project Type**: Infrastructure-as-Code with a single OpenTofu root and a small bootstrap script set. Not a library, service, or app.

**Performance Goals** (operational, not throughput-based):

- Initial `tofu apply` of the hub: ≤ 60 minutes wall clock, dominated by VPN gateway provisioning (Azure-side, not the pipeline).
- Incremental spoke add `tofu apply`: ≤ 10 minutes wall clock.
- `tofu plan` on PR (static): ≤ 2 minutes wall clock.

**Constraints**:

- All provider and module versions pinned with `~>` constraints in `versions.tf`; module sources include explicit version tags.
- No long-lived secrets anywhere — repo, state, pipeline, or VPN profile (FR-013, FR-014, FR-015, FR-016a).
- No manual portal/CLI changes against the platform once it is deployed (FR-018).
- Steady-state idle hub cost target: ≤ $350/month at the chosen minimum SKUs (VpnGw1 ≈ $140, DNS Private Resolver inbound endpoint ≈ $130, Log Analytics workspace + validation VM + storage PE ≈ $25–$50). Recorded in `docs/cost-baseline.md` and reviewed on every PR that adds an always-on resource (SC-007).

**Scale/Scope**:

- Designed for ≤ 10 spokes in practice; the default `10.x.0.0/22` allocation supports ≤ 254 before exhausting the second octet. Address scheme can be extended trivially.
- Designed for ≤ 5 subscription "slots" in practice; each slot is one static `provider "azurerm"` block in `infra/providers.tf`. Adding a new subscription is the only configuration change that requires editing HCL rather than the spokes inventory.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-evaluated after Phase 1 design.*

Evaluated against the five principles in `.specify/memory/constitution.md` v1.0.0:

| Principle | Status | Notes |
|---|---|---|
| **I. Azure Verified Modules First** | PASS w/ one justified exception | All resources except the P2S VPN gateway use the AVM Terraform module catalog at the pinned versions listed above. The VPN gateway uses native `azurerm_virtual_network_gateway`; see Complexity Tracking. |
| **II. Cost-Optimized Minimal Footprint** | PASS | VPN GW = VpnGw1 (minimum SKU compatible with OpenVPN/Entra); only the DNS Private Resolver inbound endpoint (no outbound, no forwarding ruleset); Log Analytics in the default pay-as-you-go tier with 30-day retention; validation VM = `Standard_B1s`; no NVA, no Firewall, no Bastion, no DDoS Standard, no WAF tier, no NSG flow logs. |
| **III. Secretless Entra Authentication** | PASS | GitHub Actions → Azure via OIDC workload identity federation. State backend uses `use_oidc = true` and `use_azuread_auth = true`. VPN uses Entra (OpenVPN tunnel, Microsoft-registered Azure VPN Client audience `41b23e61-6c1e-4545-b367-cd054e0ed4b4`). VM auth uses the `AADSSHLoginForLinux` extension. Storage account has `shared_access_key_enabled = false` and `default_to_oauth_authentication = true`. Deployment SP has no Microsoft Graph permissions. |
| **IV. Hub-and-Spoke Extensibility** | PASS | Address plan reserves `10.x.0.0/22` for x ∈ 2..254. Per-spoke RGs (not a shared RG) and per-sub static aliases keep blast radius and provider routing decoupled from spoke count. Hub gateway transit + spoke `use_remote_gateways` is the standard wiring; a future spoke-to-spoke transit (NVA, vWAN, or peering mesh) is a hub addition, not a redesign. Private DNS zones are hub-resourced and linked via module inputs. |
| **V. IaC Quality, Reproducibility, Automated Delivery** | PASS | OpenTofu only; providers & modules pinned; backend OIDC + AAD; PRs run plan, default branch runs apply consuming the uploaded plan; `tflint` (azurerm ruleset) and `trivy config` mandatory; the bootstrap and apply paths are the only writers to state. |

**Result**: Gate passed. One AVM escape hatch declared in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-hub-spoke-foundation/
├── plan.md              # This file
├── research.md          # Phase 0 output — technical decisions + alternatives
├── data-model.md        # Phase 1 output — variable shapes, entity attributes
├── quickstart.md        # Phase 1 output — end-to-end validation procedure
├── contracts/           # Phase 1 output — config file schemas + bootstrap input contract
│   ├── spokes-inventory.schema.md
│   ├── subscriptions-inventory.schema.md
│   └── bootstrap-inputs.md
├── checklists/
│   └── requirements.md  # Existing spec-quality checklist
└── tasks.md             # Phase 2 output (NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── plan.yml             # PR-triggered: fmt, validate, tflint, trivy, tofu plan, upload artifact
    └── apply.yml            # main-branch-triggered: download plan artifact, tofu apply

bootstrap/
├── README.md                # When to run, what it does, idempotency expectations
├── bootstrap.ps1            # Idempotent agent-run script: enumerate subs, create SP + fed creds,
│                            # assign Contributor + UAA per-sub + Storage Blob Data Contributor on state,
│                            # create VPN access Entra group, emit a *.tfvars.json with the
│                            # discovered object IDs and subscription metadata.
└── outputs/                 # Git-ignored; bootstrap.ps1 writes outputs (object IDs, sub map) here.

infra/                       # OpenTofu root
├── versions.tf              # required_version, required_providers (pinned)
├── backend.tf               # azurerm backend, OIDC + AAD auth
├── providers.tf             # default provider (hub sub) + static aliased providers (one per sub slot)
├── variables.tf
├── locals.tf                # address-space overlap detection, derived names, DNS zone list
├── main.tf                  # module "hub", for_each "spoke", module "validation_workload"
├── outputs.tf
└── modules/
    ├── hub/                 # RG, VNet, GatewaySubnet, DnsResolverSubnet, public IP, VPN GW (native),
    │                        # DNS Private Resolver inbound endpoint, Private DNS zones, Log Analytics,
    │                        # diagnostic settings (VPN GW + Resolver)
    ├── spoke/               # RG, VNet, workload subnet, NSG (VPN-pool allow), private DNS VNet links,
    │                        # bidirectional peering with hub via the AVM peering submodule
    └── workloads/
        └── validation/      # B1s Linux VM with AADSSHLoginForLinux, storage account with blob PE

config/
├── platform.auto.tfvars     # Hub sub ID, hub RG name, region, hub VNet CIDR,
│                            # VPN client address pool, DNS zone list, workspace retention
├── subscriptions.auto.tfvars # Map of subscription "slots" → IDs; one entry per provider alias
└── spokes.auto.tfvars       # Map of logical spoke name → { sub_slot, rg_name, address_space, ... }

docs/
├── architecture.md          # Topology diagram + decision rationale (links to research.md)
├── cost-baseline.md         # Steady-state monthly cost line items (SC-007)
└── adding-a-spoke.md        # Operator guide for the configuration-only spoke addition path

.tflint.hcl
.trivyignore                 # If/when needed
.tool-versions               # tofu version pin
.gitignore                   # Already present; bootstrap/outputs/ added by bootstrap step
```

**Structure Decision**: Single OpenTofu root in `infra/` (composed of a hub module, a spoke module, and a per-workload module pattern), driven by three configuration files in `config/` that the workflow loads via `*.auto.tfvars`. The bootstrap is a separate, agent-run PowerShell script in `bootstrap/` that runs once per Entra tenant (and incrementally when new subscriptions appear). This shape keeps the "add a spoke" gesture to one config edit while honoring the multi-sub provider-alias constraint described in Phase 0 research.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Native `azurerm_virtual_network_gateway` + `azurerm_public_ip` instead of an AVM module (Constitution Principle I, escape hatch (c)) | The dedicated AVM pattern module `Azure/avm-ptn-vnetgateway` was archived in October 2025. Its successor `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet` (v0.17.1, GA) is opinionated for Azure Landing Zone CAF alignment: it forces Firewall, Bastion, DDoS Standard, and a fixed connectivity-subscription shape. There is no resource-scope AVM (`avm-res-network-virtualnetworkgateway`) at GA yet; it is still in "proposed" status. | Composing the resource-scope AVMs (VNet, public IP, NSG, DNS zones, resolver, workspace, VM, storage) plus the native VPN gateway is the only shape that simultaneously honors Principle II (minimum SKU, no Firewall, no Bastion, no DDoS Standard) and Principle V (pin a stable version we can audit). The ALZ pattern would directly violate Principle II. A "wait for resource-scope AVM" approach blocks delivery indefinitely. This native fallback will be re-evaluated whenever the AVM index publishes `avm-res-network-virtualnetworkgateway` at GA. |
