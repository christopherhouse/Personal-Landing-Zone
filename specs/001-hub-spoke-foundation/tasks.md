---
description: "Task list for Hub-and-Spoke Networking Foundation"
---

# Tasks: Hub-and-Spoke Networking Foundation

**Input**: Design documents from `/specs/001-hub-spoke-foundation/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: The spec does not request automated test code. Static-analysis gates (`tofu fmt -check`, `tofu validate`, `tflint`, `trivy config`) are treated as the pre-merge "test" surface; end-to-end behavior is validated against `quickstart.md`. No `tests/` tree is produced.

**Organization**: Tasks are grouped by user story. Phase 1 (Setup) and Phase 2 (Foundational) must complete before any user story phase begins. Within a phase, tasks marked `[P]` touch different files and can run in parallel.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different files, no in-phase dependencies on incomplete tasks.
- **[Story]**: User-story label (US1, US2, US3) — present only inside story phases.

## Path Conventions

Single OpenTofu root in `infra/`, three configuration files in `config/`, one bootstrap script in `bootstrap/`, three GitHub Actions workflows in `.github/workflows/`. All paths are repository-relative.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Skeleton repository scaffold and tool-version pinning.

- [x] T001 Create the directory skeleton: `.github/workflows/`, `bootstrap/`, `bootstrap/outputs/`, `infra/`, `infra/modules/hub/`, `infra/modules/spoke/`, `infra/modules/workloads/validation/`, `config/`, `docs/`
- [x] T002 [P] Create `.tool-versions` pinning `opentofu 1.9.0` (or current 1.9.x) at the repo root
- [x] T003 [P] Update `.gitignore` at the repo root: REMOVE the line that ignores `**/.terraform.lock.hcl` (lock files must be committed per Constitution Principle V); ADD `bootstrap/outputs/*` with an exception for `bootstrap/outputs/.gitkeep`; ADD `infra/tfplan` and `infra/*.tfplan`
- [x] T004 [P] Create `.tflint.hcl` at the repo root with `plugin "azurerm"` (source = `terraform-linters/tflint-ruleset-azurerm`, version pinned) enabled and the `terraform_required_providers` + `terraform_required_version` rules turned on
- [x] T005 [P] Create `infra/README.md` describing the root-and-three-modules composition with a one-paragraph link map back to `specs/001-hub-spoke-foundation/plan.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: OpenTofu root scaffold, OIDC backend, provider aliases, variable + locals validation, bootstrap script, and the two core GitHub Actions workflows. Nothing in any user story phase can run before this is complete.

**⚠️ CRITICAL**: No user-story task may begin until every Phase 2 task is checked.

### OpenTofu root scaffold

- [x] T006 Create `infra/versions.tf` with `required_version >= 1.9.0` and `required_providers` pinning `hashicorp/azurerm ~> 4.20`, `Azure/azapi ~> 2.4`, `hashicorp/random ~> 3.5`, `Azure/modtm ~> 0.3`
- [x] T007 Create `infra/backend.tf` with an `azurerm` backend block in partial mode (no hard-coded coordinates) and `use_oidc = true`, `use_azuread_auth = true` — coordinates are injected via `-backend-config=` at `tofu init` time in `apply.yml` and `plan.yml`
- [x] T008 Create `infra/providers.tf` with: (a) the default `provider "azurerm"` block (also OIDC + AAD), pointed at the hub subscription via `subscription_id = var.subscription_slots["hub"].subscription_id`; (b) one aliased block `provider "azurerm" { alias = "sub_hub" ... }` configured identically. Add a header comment documenting that adding a new subscription requires copying the `sub_hub` block, renaming the alias to `sub_<slot_name>`, and pointing it at the matching slot's `subscription_id`.
- [x] T009 Create `infra/variables.tf` declaring three top-level variables — `platform` (object), `subscription_slots` (map of object), `spokes` (map of object) — with field shapes per `data-model.md`. Include `validation {}` blocks for: GUID format on `tenant_id`, `hub_subscription_id`, `vpn_access_group_object_id`; CIDR format on `hub_address_space` and `vpn_client_address_pool`; name pattern on `hub_resource_group_name`; non-empty `dns_zones`.
- [x] T010 Create `infra/locals.tf` with: (a) `address_blocks` list assembled from hub CIDR + VPN pool + every spoke address space + every workload subnet prefix; (b) a `check { ... }` block (or `precondition` via a `null_resource` if check-block syntax isn't available) that asserts pairwise non-overlap and emits the conflicting pair on failure; (c) a check that every distinct `subscription_slot` referenced by a spoke exists as a key in `subscription_slots`; (d) a check that spoke names + spoke RG names are unique across the inventory; (e) a check that at most one spoke has `include_validation_workload = true`; (f) derived locals for naming (`hub_vnet_name`, etc.) keyed off `var.platform.naming_prefix`.
- [x] T011 Create `infra/outputs.tf` as an empty file with a header comment — populated in Phase 3 once the hub module exists.

### Bootstrap script

- [x] T012 Create `bootstrap/bootstrap.ps1` with the parameter block matching `contracts/bootstrap-inputs.md` (`-TenantId`, `-HubSubscriptionId`, `-HubResourceGroupName`, `-StateSubscriptionId`, `-StateResourceGroupName`, `-StateStorageAccountName`, `-StateContainerName`, `-GithubRepository`, `-GithubBranchOrEnvironment` (repeatable string array), optional `-DeploymentAppDisplayName`, `-VpnAccessGroupDisplayName`, `-Region`). Add the pre-flight check block: verify `az` is logged in, tenant matches, state account is reachable.
- [x] T013 Implement subscription enumeration in `bootstrap/bootstrap.ps1`: call `az account list --query "[?tenantId=='$TenantId']" -o json`, derive slot names via lowercase-and-slugify of each subscription's `name`, force the hub sub's slot to `hub`. Store in `$slotMap`.
- [x] T014 Implement deployment Entra app + service principal + federated credential creation in `bootstrap/bootstrap.ps1`: idempotent `az ad app create`, idempotent `az ad sp create`, and one `az ad app federated-credential create` per `-GithubBranchOrEnvironment` value. Capture `$appId`, `$spObjectId`. NO client secret may be created at any point.
- [x] T015 Implement VPN access group creation in `bootstrap/bootstrap.ps1`: idempotent `az ad group create --display-name $VpnAccessGroupDisplayName --mail-nickname <sanitized>`; capture `$vpnGroupObjectId`.
- [x] T016 Implement role assignments in `bootstrap/bootstrap.ps1`: for each subscription in `$slotMap`, idempotently create `Contributor` and `User Access Administrator` at `/subscriptions/<id>` for `$spObjectId`. Then idempotently create `Storage Blob Data Contributor` for `$spObjectId` on the state storage account's resource ID.
- [x] T017 Implement output writers in `bootstrap/bootstrap.ps1`: write `bootstrap/outputs/discovered.auto.tfvars.json` with `subscription_slots`, `vpn_access_group_object_id`, `deployment_app_client_id`, `tenant_id`; write `bootstrap/outputs/bootstrap-report.md` summarizing every object created vs. left alone, including federated-credential subjects, role-assignment scopes, and the GitHub Variables the operator must set.
- [x] T018 Create `bootstrap/README.md` documenting when to run the script, the four input categories (operator-supplied vs. auto-discovered vs. defaults vs. optional), re-run semantics, and the contract reference to `contracts/bootstrap-inputs.md`.

### Workflows

- [x] T019 [P] Create `.github/workflows/plan.yml` triggered on `pull_request` against the default branch with `permissions: id-token: write, contents: read`. Jobs in order: checkout → `opentofu/setup-opentofu@v1` (version pinned) → `azure/login@v2` (OIDC) → `tofu init -backend-config=...` (state coordinates from repo Variables) → `tofu fmt -check -recursive` → `tofu validate` → `tflint --recursive` → `trivy config infra/` → `tofu plan -out=tfplan -input=false`. Upload `tfplan` and `tofu show -no-color tfplan > plan.txt` as a workflow artifact named `tfplan-${{ github.event.pull_request.number }}`.
- [x] T020 [P] Create `.github/workflows/apply.yml` triggered on `push` to the default branch with `permissions: id-token: write, contents: read, actions: read, pull-requests: read`. Jobs: checkout → setup-opentofu → azure/login (OIDC) → look up the merge-commit's source PR via `gh pr list` → download artifact `tfplan-<pr_number>` → `tofu init -backend-config=...` → `tofu apply -input=false tfplan`. Fail loudly if no matching artifact is found.

**Checkpoint**: Foundation complete. The repo has a valid OTF root that `tofu init` and `tofu validate` cleanly with empty inventories, a runnable bootstrap, and PR+apply pipelines. User stories may now begin.

---

## Phase 3: User Story 1 — First-time deployment of hub + initial spoke (Priority: P1) 🎯 MVP

**Goal**: A merged-and-applied initial PR brings up the hub (VNet, P2S VPN gateway, DNS Private Resolver inbound endpoint, Private DNS zones, Log Analytics workspace) and one spoke (the `validation` spoke) containing the Linux VM + storage account with blob private endpoint. Connecting to the VPN and running `nslookup`+`az ssh vm`+`az storage blob list` succeeds end-to-end with no manual portal steps after bootstrap.

**Independent Test**: `quickstart.md` Part 1 (steps 1.2 – 1.7) completes without failures.

### Hub module — split across multiple files for clean diffs

- [ ] T021 [US1] Create `infra/modules/hub/variables.tf` declaring inputs that surface every knob from `data-model.md`'s Platform entity table that the hub needs (subscription_id, resource_group_name, region, address_space, dns_zones, workspace_retention_days, naming_prefix, vpn_client_address_pool, tenant_id, vpn_access_group_object_id, tags)
- [ ] T022 [P] [US1] Implement hub RG using `Azure/avm-res-resources-resourcegroup/azurerm ~> 0.4` (`enable_telemetry = false`) in `infra/modules/hub/rg.tf`
- [ ] T023 [P] [US1] Implement hub VNet using `Azure/avm-res-network-virtualnetwork/azurerm ~> 0.17` in `infra/modules/hub/vnet.tf` with three subnets: `GatewaySubnet` (`/27`, no NSG), `AzureDnsResolverInbound` (`/28`, delegated to `Microsoft.Network/dnsResolvers`, no NSG), and `snet-${prefix}-hub-reserve` (`/24`). Use the AVM `subnets` map.
- [ ] T024 [P] [US1] Implement the gateway public IP using `Azure/avm-res-network-publicipaddress/azurerm ~> 0.2` (Standard SKU, Static allocation) in `infra/modules/hub/gateway.tf`
- [ ] T025 [US1] Add the native `azurerm_virtual_network_gateway` resource to `infra/modules/hub/gateway.tf` with `type = "Vpn"`, `vpn_type = "RouteBased"`, `sku = "VpnGw1"`, `generation = "Generation2"`, an `ip_configuration` referencing the GatewaySubnet + the public IP from T024, and `vpn_client_configuration` containing: `address_space = [var.vpn_client_address_pool]`, `vpn_client_protocols = ["OpenVPN"]`, `aad_tenant = "https://login.microsoftonline.com/${var.tenant_id}/"`, `aad_audience = "41b23e61-6c1e-4545-b367-cd054e0ed4b4"`, `aad_issuer = "https://sts.windows.net/${var.tenant_id}/"`, and **`additional_dns_servers = [<DNS Private Resolver inbound endpoint IP from T026's output>]`** — this is the field that pushes the resolver IP to the Azure VPN client and satisfies FR-005 / FR-007. Use the exact AVM output name from T026 (commonly `module.<resolver>.inbound_endpoint_ips[0]` or equivalent — verify against the resolver AVM's outputs when wiring). Sequential after T024 (same file) and depends on T026 having declared its outputs.
- [ ] T026 [P] [US1] Implement DNS Private Resolver inbound endpoint using `Azure/avm-res-network-dnsresolver/azurerm ~> 0.8` in `infra/modules/hub/resolver.tf` with one `inbound_endpoints` entry pointing at the `AzureDnsResolverInbound` subnet (dynamic IP assignment) and zero `outbound_endpoints`. Confirm the module exposes the assigned inbound endpoint IP as an output (used by T025).
- [ ] T027 [P] [US1] Implement Private DNS zones using `Azure/avm-res-network-privatednszone/azurerm ~> 0.5` in `infra/modules/hub/dns.tf`, with one module instance per name in `var.dns_zones`. Include a `virtual_network_links` entry that links the hub VNet itself (so the inbound resolver can resolve every zone).
- [ ] T028 [P] [US1] Implement the Log Analytics workspace using `Azure/avm-res-operationalinsights-workspace/azurerm ~> 0.5` in `infra/modules/hub/observability.tf` with `sku = "PerGB2018"`, `retention_in_days = var.workspace_retention_days`
- [ ] T029 [US1] Add diagnostic settings in `infra/modules/hub/observability.tf` — one for the VPN gateway (categories: `GatewayDiagnosticLog`, `TunnelDiagnosticLog`, `RouteDiagnosticLog`, `IKEDiagnosticLog`, `P2SDiagnosticLog`; all metrics) routed to the workspace; one for the DNS Private Resolver inbound endpoint (all available categories + metrics) routed to the workspace. Use AVM modules' built-in `diagnostic_settings` inputs where available; fall back to native `azurerm_monitor_diagnostic_setting` if the AVM module doesn't expose the relevant categories. Sequential after T028 (same file).
- [ ] T030 [US1] Create `infra/modules/hub/outputs.tf` exposing: `vnet_id`, `vnet_name`, `gateway_subnet_id`, `vpn_gateway_id`, `vpn_gateway_name`, `resolver_inbound_endpoint_ip`, `private_dns_zone_ids` (map keyed by zone name), `private_dns_zone_resource_group_name`, `workspace_id`, `workspace_resource_id`

### Spoke module — split across multiple files

- [ ] T031 [US1] Create `infra/modules/spoke/variables.tf` declaring: `spoke_name`, `resource_group_name`, `region`, `address_space`, `workload_subnet_prefix`, `naming_prefix`, `hub_vnet_id`, `hub_vnet_resource_group_name`, `hub_private_dns_zone_ids` (map), `vpn_client_address_pool`, `tags`
- [ ] T032 [P] [US1] Implement spoke RG using the resource-group AVM in `infra/modules/spoke/rg.tf`
- [ ] T033 [P] [US1] Implement spoke VNet using the VNet AVM in `infra/modules/spoke/vnet.tf` with one `subnets` entry — name `"snet-${prefix}-spoke-${spoke_name}-workload"`, address prefix `var.workload_subnet_prefix`, `network_security_group_id` referencing the NSG from T034
- [ ] T034 [P] [US1] Implement workload NSG using `Azure/avm-res-network-networksecuritygroup/azurerm ~> 0.5` in `infra/modules/spoke/nsg.tf` with exactly one inbound `security_rule`: name `Allow-VpnClientPool-Any`, priority `100`, direction `Inbound`, access `Allow`, protocol `*`, source_address_prefix `var.vpn_client_address_pool`, source/destination_port_range `*`, destination_address_prefix `*`.
- [ ] T035 [P] [US1] Implement bidirectional peering using the AVM peering submodule `Azure/avm-res-network-virtualnetwork/azurerm//modules/peering` in `infra/modules/spoke/peering.tf` with `create_reverse_peering = true`, hub-side `allow_gateway_transit = true`, spoke-side `use_remote_gateways = true`. Pass `providers = { azurerm = azurerm, azurerm.hub = azurerm.hub }` through `configuration_aliases` (the hub provider is forwarded from the root).
- [ ] T036 [P] [US1] Implement private DNS VNet links in `infra/modules/spoke/dns-links.tf` — one `azurerm_private_dns_zone_virtual_network_link` per zone ID in `var.hub_private_dns_zone_ids`, with `registration_enabled = false`. Use the hub provider alias (zone lives in hub sub). Note: link-conflict handling (Edge Case: "Private DNS zone already linked elsewhere") is delegated to the Azure API's natural error response — no explicit pre-check; see `research.md` R-006.
- [ ] T037 [US1] Create `infra/modules/spoke/outputs.tf` exposing `vnet_id`, `vnet_name`, `workload_subnet_id`, `resource_group_name`

### Validation workload module — split across files

- [ ] T038 [P] [US1] Create `infra/modules/workloads/validation/variables.tf` declaring `target_resource_group_name`, `target_subnet_id`, `target_private_dns_zone_id_blob` (for the storage PE's zone group), `vpn_access_group_object_id`, `region`, `naming_prefix`, `tags`
- [ ] T039 [P] [US1] Implement the validation VM using `Azure/avm-res-compute-virtualmachine/azurerm ~> 0.20` in `infra/modules/workloads/validation/vm.tf`: `Standard_B1s`, Ubuntu 22.04 LTS Gen 2 (Canonical image), system-assigned managed identity enabled, one network interface in `var.target_subnet_id`, `disable_password_authentication = true`, a throwaway public SSH key generated via `tls_private_key` (provider `hashicorp/tls`) whose private half is NOT persisted. Include an `extensions` map entry for `AADSSHLoginForLinux`: publisher `Microsoft.Azure.ActiveDirectory`, type `AADSSHLoginForLinux`, type_handler_version `1.0`, auto-upgrade minor version true.
- [ ] T040 [P] [US1] Implement the storage account using `Azure/avm-res-storage-storageaccount/azurerm ~> 0.7` in `infra/modules/workloads/validation/storage.tf` with: `account_kind = "StorageV2"`, `account_tier = "Standard"`, `account_replication_type = "LRS"`, `shared_access_key_enabled = false`, `default_to_oauth_authentication = true`, `public_network_access_enabled = false`, `min_tls_version = "TLS1_2"`. Inline `private_endpoints = { blob = { ... } }` targeting `var.target_subnet_id` and registering the A record in `var.target_private_dns_zone_id_blob`. Add a `containers = { validation = { ... } }` map for a single `validation` container.
- [ ] T041 [P] [US1] Implement role assignments in `infra/modules/workloads/validation/rbac.tf`: `azurerm_role_assignment` granting `Virtual Machine User Login` on the VM scope to `var.vpn_access_group_object_id`; `azurerm_role_assignment` granting `Storage Blob Data Reader` on the storage account scope to `var.vpn_access_group_object_id`.
- [ ] T042 [US1] Create `infra/modules/workloads/validation/outputs.tf` exposing `vm_name`, `vm_resource_id`, `storage_account_name`, `blob_private_endpoint_fqdn`

### Root composition

- [ ] T043 [US1] Add `module "hub"` invocation to `infra/main.tf` with `providers = { azurerm = azurerm.sub_hub }`, passing every input from `var.platform` plus the discovered VPN access group object ID
- [ ] T044 [US1] Add `for_each` `module "spoke"` invocation to `infra/main.tf` iterating over `var.spokes` and routing the provider via `providers = { azurerm = ... }` resolved from each spoke's `subscription_slot`. Implementation note: since OpenTofu cannot dynamically select a provider in `for_each`, use the static-alias-per-slot pattern from `research.md` R-003 — wrap the spoke module call in a `for_each` per slot, where each block filters `var.spokes` to entries matching that slot and passes the matching alias. For Phase 3 MVP, only the `hub` slot is in use.
- [ ] T045 [US1] Add `module "validation_workload"` invocation to `infra/main.tf`, scoped to the single spoke that has `include_validation_workload = true` (use a `for_each` over `{ for k, v in var.spokes : k => v if v.include_validation_workload }`). Pass `target_resource_group_name`, `target_subnet_id` (from the spoke module's output), `target_private_dns_zone_id_blob` (from the hub module's `private_dns_zone_ids["privatelink.blob.core.windows.net"]`), and `vpn_access_group_object_id` from `var.platform`.
- [ ] T046 [US1] Populate `infra/outputs.tf` exposing: `vpn_gateway_name`, `vpn_client_address_pool`, `resolver_inbound_endpoint_ip`, `validation_vm_name` (conditional on workload existing), `validation_storage_account_name`, `validation_blob_private_endpoint_fqdn`

### Initial configuration

- [ ] T047 [P] [US1] Author `config/platform.auto.tfvars` with the hub coordinates (placeholders for `subscription_id` and `tenant_id` — replaced post-bootstrap), `region = "eastus2"`, `hub_address_space = "10.0.0.0/22"`, `vpn_client_address_pool = "10.255.0.0/16"`, `dns_zones = ["privatelink.blob.core.windows.net", "privatelink.vaultcore.azure.net", "plz.internal"]`, `workspace_retention_days = 30`, `naming_prefix = "plz"`, `github_repo = "<owner>/<repo>"`, empty `tags`. Leave `vpn_access_group_object_id` as a placeholder string commented `# populated by bootstrap`.
- [ ] T048 [P] [US1] Author `config/spokes.auto.tfvars` with one entry: spoke `validation` → `subscription_slot = "hub"`, `resource_group_name = "rg-plz-spoke-validation-eastus2"`, `address_space = "10.1.0.0/22"`, `workload_subnet_prefix = "10.1.0.0/24"`, `include_validation_workload = true`

### End-to-end bring-up

- [ ] T049 [US1] On a fresh feature branch, run `bootstrap/bootstrap.ps1` end-to-end against the operator's `az login` session. Review `bootstrap/outputs/bootstrap-report.md`. Set the repository Variables (`ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`, `TF_STATE_*`) in GitHub. Commit `bootstrap/outputs/discovered.auto.tfvars.json` to the branch.
- [ ] T050 [US1] Open the initial deployment PR. Confirm `plan.yml` succeeds and the plan diff in the artifact matches expectations. Merge to default branch. `apply.yml` runs — initial apply takes ~30–45 min due to VPN gateway provisioning (Edge Cases: "VPN gateway provisioning latency"). Confirm completion.
- [ ] T051 [US1] Execute `quickstart.md` Part 1 steps 1.2 – 1.7 on the operator's workstation: import VPN profile, connect, validate DNS resolution of the blob private endpoint and the VM A record, `az ssh vm` to the VM, `az storage blob list --auth-mode login`. Record results in a comment on the PR (or a follow-up issue) as evidence for SC-001.

**Checkpoint**: User Story 1 is independently validated end-to-end. The MVP is shippable.

---

## Phase 4: User Story 2 — Add a new spoke through configuration only (Priority: P1)

**Goal**: The operator edits `config/spokes.auto.tfvars` to add one new spoke (in any subscription slot that already has a provider alias declared), opens a PR, sees a clean plan diff posted as a PR comment, merges, and after the apply the new spoke is route-reachable and DNS-resolvable from the VPN — without editing any existing spoke's definition.

**Independent Test**: `quickstart.md` Part 2 (steps 2.1 – 2.4) plus the negative tests in Part 3 complete without failures.

Most of the implementation work for US2 was already done in US1 (the spoke module is generic; `for_each` is in place; locals.tf validations are in place). Two remaining tasks make US2 production-ready:

- [ ] T052 [US2] Extend `.github/workflows/plan.yml` with a final `actions/github-script@v7` step that downloads `plan.txt`, formats it (truncated to ≤ 65 KiB to fit a GitHub comment), and posts it as a sticky comment on the PR (`<!-- speckit-tfplan -->` marker) so subsequent pushes update the same comment rather than spam. Required for the operator to review the plan diff before merging (FR-020).
- [ ] T053 [P] [US2] Author `docs/adding-a-spoke.md` walking through: (a) the same-sub flow (edit `config/spokes.auto.tfvars` only) with a copy-paste-ready example; (b) the cross-sub flow (add a slot to `config/subscriptions.auto.tfvars` + add a `provider "azurerm" { alias = "sub_<slot>" }` block to `infra/providers.tf` + edit `config/spokes.auto.tfvars`) with a copy-paste-ready example. Reference `contracts/spokes-inventory.schema.md`.

### End-to-end validation

- [ ] T054 [US2] Execute `quickstart.md` Part 2 (steps 2.1 – 2.4): add a `smoketest` spoke at `10.2.0.0/22`, open + merge a PR, confirm a clean `~5 minute` apply, then confirm the VPN client has a route for `10.2.0.0/22` (route table on Windows or refreshed profile). Then run the three negative tests in `quickstart.md` Part 3 (3.1 overlap, 3.2 duplicate RG name, 3.3 unknown slot) and confirm each is rejected at plan time with the documented error message.

**Checkpoint**: User Stories 1 AND 2 are independently testable and both pass.

---

## Phase 5: User Story 3 — Reproducible teardown and redeployment (Priority: P2)

**Goal**: The operator can destroy the entire platform on demand and redeploy it from the same configuration to the same observable state.

**Independent Test**: `quickstart.md` Part 4 (teardown rehearsal) completes successfully.

- [ ] T055 [US3] Create `.github/workflows/destroy.yml` triggered by `workflow_dispatch` with `permissions: id-token: write, contents: read`. Jobs: checkout → setup-opentofu → azure/login (OIDC) → `tofu init -backend-config=...` → `tofu plan -destroy -out=destroyplan -input=false` → upload the destroy plan as an artifact → `tofu apply -input=false destroyplan`. Add an `environment:` block (e.g., `environment: destroy`) so the operator can require manual approval per GitHub environment protection rules.
- [ ] T056 [P] [US3] Author `docs/teardown.md` documenting: when to run `destroy.yml`, what it removes (everything in the spoke RGs + the hub RG; nothing in the state account itself), the expected ~15-minute duration (VPN gateway deletion dominates), and the verification steps post-destroy (Azure portal RG listing, plus `tofu state list` should return zero resources).
- [ ] T057 [US3] Execute `quickstart.md` Part 4: trigger `destroy.yml`, confirm the destroy plan in the artifact, approve the environment gate, watch destruction complete, then re-trigger `apply.yml`. After the new apply finishes, re-execute `quickstart.md` Part 1 steps 1.2 – 1.7 and confirm SC-006 passes.

**Checkpoint**: All three user stories independently functional. Platform meets SC-001 through SC-006.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cost evidence, tflint/trivy tuning, secret-leak scan. Improvements that affect multiple user stories.

- [ ] T058 [P] Author `docs/architecture.md` containing: a topology diagram (ASCII or Mermaid) showing hub + slots + spokes + the VPN tunnel + DNS query flow; a one-paragraph "how to read this" section; a "decisions" subsection summarizing R-001 through R-013 from `research.md` with stable anchor links.
- [ ] T059 [P] Author `docs/cost-baseline.md` materializing the table from `research.md` R-012 with current Azure pricing for the operator's region (eastus2 by default). Include a "How this is reviewed" subsection that names the PR-review trigger from SC-007 (any PR that adds an always-on resource).
- [ ] T060 [P] Tune `.tflint.hcl` to additionally enable the `azurerm_storage_account_invalid_*` rules, `terraform_module_pinned_source` (warn level), and `terraform_unused_declarations`. Set `tflint --recursive` as the canonical invocation; verify it passes against the current tree.
- [ ] T061 [P] Run `trivy config infra/ --format table` against the current tree; for any genuine false positives, add suppression entries to `.trivyignore` with one-line rationales. For real findings, file as TODOs (do not suppress).
- [ ] T062 [P] Update repository-root `README.md` with: a one-paragraph "what is this" intro pointing at `specs/001-hub-spoke-foundation/spec.md`; a "first-time setup" pointer to `bootstrap/README.md`; an "adding a spoke" pointer to `docs/adding-a-spoke.md`; a "validating the deployment" pointer to `specs/001-hub-spoke-foundation/quickstart.md`; a "governance" pointer to `.specify/memory/constitution.md`.
- [ ] T063 Confirm SC-005 (zero long-lived secrets) by: (a) running `gitleaks detect --source . --no-banner` (or `trufflehog filesystem .`) against the repo and confirming zero findings; (b) running `az ad app credential list --id $deploymentAppId` and confirming zero password credentials; (c) running `az storage account keys list -n $stateAccount` against the state account (the SP cannot, but the operator can) and confirming the keys exist (Azure-side, unavoidable) but that no GitHub secret, no tfvars file, and no workflow uses them. Record evidence in a follow-up `docs/secret-audit.md` file.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: no dependencies; can start immediately.
- **Phase 2 (Foundational)**: depends on Phase 1; BLOCKS every user story.
- **Phase 3 (US1, P1)**: depends on Phase 2.
- **Phase 4 (US2, P1)**: depends on Phase 3 (US2 builds on the spoke module and the deployed hub; you cannot demonstrate "add a spoke" before there's a hub).
- **Phase 5 (US3, P2)**: depends on Phase 4 being shippable (you tear down a working platform, not an empty one).
- **Phase 6 (Polish)**: starts after Phase 3 minimum; T058–T062 can run in parallel with Phase 4 or Phase 5 work.

### User story dependencies

- **US1** is the foundation. Everything else assumes it.
- **US2** is logically additive to US1 — same modules, more invocations. The two are co-equal P1 in the spec, but executionally US2 sits on top of US1.
- **US3** depends on US1 + US2 to be meaningful (you tear down and redeploy a working multi-spoke platform).

### Within each phase

- Setup: T001 first (directory must exist); T002–T005 then parallel.
- Foundational: T006–T011 (OTF scaffold) sequential within `infra/` because they reference each other's symbols; T012–T018 (bootstrap) is one PowerShell file authored top-down; T019/T020 (workflows) are independent of each other and of the OTF scaffold.
- US1 hub module (T022–T029): tasks marked `[P]` are in separate files and can run in parallel; sequential dependencies are inside the same file (T024 → T025 in `gateway.tf`; T028 → T029 in `observability.tf`). T025 additionally depends on T026 (the VPN gateway needs the resolver IP as `additional_dns_servers`), but since these are in different files the dependency is at apply time, not authorship time — T026 can be authored first or in parallel with T024.
- US1 spoke module (T032–T036): all `[P]` because each is its own file.
- US1 validation workload (T039–T041): all `[P]` because each is its own file.
- US1 root composition (T043–T046): sequential — all in `infra/main.tf` + `infra/outputs.tf`.
- US1 end-to-end (T049–T051): strictly sequential (bootstrap → PR → quickstart).

### Parallel opportunities (concrete)

Within US1, after T021 + T031 + T038 are checked, the following can be authored in parallel by separate workers (or in a single session by an LLM dispatching independent edits):

```
T022 (hub/rg.tf)         T032 (spoke/rg.tf)         T039 (validation/vm.tf)
T023 (hub/vnet.tf)       T033 (spoke/vnet.tf)       T040 (validation/storage.tf)
T024 (hub/gateway.tf)    T034 (spoke/nsg.tf)        T041 (validation/rbac.tf)
T026 (hub/resolver.tf)   T035 (spoke/peering.tf)
T027 (hub/dns.tf)        T036 (spoke/dns-links.tf)
T028 (hub/observability.tf)
T047 (config/platform.auto.tfvars)
T048 (config/spokes.auto.tfvars)
```

That's ~14 tasks executable in parallel mid-US1.

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (especially the bootstrap script — this is the gate)
3. Complete Phase 3: User Story 1
4. **Stop and validate**: execute `quickstart.md` Part 1 end-to-end. SC-001 must pass.
5. Ship MVP. The operator can now demo any single-spoke validation.

### Incremental delivery

1. After MVP, Phase 4 (US2) is small (3 tasks) and delivers the "add a spoke is trivial" headline of the platform.
2. Phase 5 (US3) adds the safety net for cost-sensitive operators who want to tear the lab down between demo cycles.
3. Phase 6 (Polish) can interleave with US2/US3 or come last — it is presentation, evidence, and hygiene rather than capability.

### Why no parallel-team strategy

Single-operator personal lab. The "team" is one operator + the agent. The parallel-execution callouts above are for an LLM dispatching independent file edits in one session, not for staffing.

---

## Notes

- `[P]` tasks are different files and have no in-phase dependencies on incomplete tasks.
- `[Story]` label maps each task back to a user story for traceability.
- Tests are intentionally OPTIONAL — the spec did not request automated test code. Static-analysis gates + `quickstart.md` cover what would otherwise be unit/contract/integration tests.
- Every implementation task names exact file paths; an agent or human can act on each task in isolation.
- Commit after each completed task or coherent group (e.g., a whole module). The `after_implement` hook is wired for this in `.specify/extensions.yml`.
- Avoid: vague tasks ("set up the hub"), same-file conflicts that the `[P]` marker hides, cross-story dependencies that would break the independence of US1.
