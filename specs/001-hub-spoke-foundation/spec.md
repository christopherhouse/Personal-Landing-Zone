# Feature Specification: Hub-and-Spoke Networking Foundation

**Feature Branch**: `001-hub-spoke-foundation`

**Created**: 2026-06-04

**Status**: Draft

**Input**: User description: Build a personal Azure hub-and-spoke virtual
network platform that serves as a persistent networking foundation for demo
workloads. The hub provides a P2S VPN gateway and centralized private DNS;
spokes are lightweight VNets peered to the hub, each one hosting an
independent demo workload. From the VPN the operator must be able to resolve
private DNS names and reach private IPs in the hub and in every spoke,
without manual client-side configuration. Adding a new spoke must be a
configuration-only change. The initial deployment includes the hub plus one
spoke containing a small validation workload for end-to-end validation. All
authentication (CI/CD, IaC state, VPN) uses Entra ID with no long-lived
secrets. Deployment is via a GitHub Actions pipeline against a single Azure
subscription.

## Clarifications

### Session 2026-06-04

- Q: How does the operator authenticate to the test VM after SSHing over the VPN? → A: Microsoft Entra ID login via the Azure AD login extension on the Linux VM; access gated by Azure RBAC role (`Virtual Machine User Login` / `Administrator Login`). No SSH keys, no Bastion.
- Q: What is the default data-plane access posture from the VPN client pool to hub and spoke resources? → A: "Trust the VPN pool" — every spoke's workload subnet gets a platform-managed NSG that allows all inbound traffic from the VPN client pool CIDR and denies all other inbound. Workloads do not need to declare exposed ports in the spoke configuration entry.
- Q: How is the VPN tunnel routed on the client side? → A: Split-tunnel. The VPN profile advertises only the hub VNet CIDR, all spoke VNet CIDRs, and the inbound DNS resolver IP as routed prefixes; all other traffic from the laptop bypasses the tunnel. DNS for hub-managed zones is directed to the inbound resolver via the VPN profile.
- Q: What diagnostic logging / observability does the platform deploy by default? → A: Minimal hub workspace — a single Log Analytics workspace in the hub, with diagnostic settings on the P2S VPN gateway and the DNS Private Resolver only. Spokes get no platform-default diagnostic settings; NSG flow logs are NOT deployed by default.
- Q: Where does the IaC state backend live relative to the platform subscription? → A: The state storage account already exists; its subscription, resource group, account name, and container are supplied to the agent at bootstrap. The spec does not require state to be in the same subscription as the platform — the deployment identity's RBAC MUST be scoped so it can access the state account wherever it lives (cross-subscription is acceptable).
- Q: What is the subscription and resource-group layout for the hub and for spokes? → A: Multi-subscription model. The operator supplies one (subscription ID, resource group name) tuple for the hub at bootstrap; the platform creates that resource group. Each spoke configuration entry declares its own (subscription ID, resource group name, address space, ...) and the platform creates that resource group in the declared subscription. Spokes are not required to live in the hub's subscription, and different spokes may live in different subscriptions. The deployment identity MUST hold Contributor + User Access Administrator at subscription scope on every subscription the operator owns (enumerated at bootstrap via `az account list`), plus Storage Blob Data Contributor on the existing state storage account. Bootstrap (SP creation, federated credentials, role assignments) is performed by the agent, not the operator.
- Q: Who creates and owns the VPN access Entra group? → A: The agent creates the group as part of bootstrap (using the operator's interactive Entra session, not the deployment SP); its object ID becomes a pipeline input. The deployment SP is NOT granted any Microsoft Graph permissions and never touches the group's lifecycle or membership. Group membership is managed by the operator out-of-band (portal / CLI / PIM).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First-time deployment of hub + initial spoke (Priority: P1)

As the operator, I want to deploy the hub and one spoke containing a small
validation workload so that I can connect via P2S VPN and verify, end-to-end,
that private DNS resolution and private connectivity work across the
hub-spoke boundary.

**Why this priority**: This is the MVP. Without a working hub + one
validated spoke, the platform delivers no value and none of the later
scenarios can be exercised. Everything else builds on this slice.

**Independent Test**: Fully testable in isolation. After the CI pipeline
finishes the initial apply, the operator downloads the VPN profile, connects
from a laptop, and on the first attempt (a) resolves the private DNS name
of the validation workload in the spoke, and (b) opens a private-IP session
(SSH/RDP/HTTPS as appropriate) to the validation workload. No hosts file
edits, no manual DNS server entries.

**Acceptance Scenarios**:

1. **Given** the operator has merged the initial deployment PR to the
   default branch, **When** the GitHub Actions deployment workflow completes
   successfully, **Then** the hub VNet, P2S VPN gateway, private DNS
   infrastructure, and the initial spoke (including its validation workload)
   all exist and are healthy.
2. **Given** the deployment is complete and the operator's Entra account
   has been granted VPN access, **When** the operator downloads the
   VPN client profile and connects, **Then** the VPN session establishes
   without prompting for any shared secret or pre-shared key.
3. **Given** the operator is connected to the VPN, **When** the operator
   resolves the validation workload's fully qualified private DNS name
   from the client machine, **Then** the resolver returns the workload's
   private IP address.
4. **Given** the operator is connected to the VPN, **When** the operator
   initiates a private-IP session to the validation workload on its
   documented service port, **Then** the session succeeds within ten
   seconds.

---

### User Story 2 - Add a new spoke through configuration only (Priority: P1)

As the operator, I want to add a new spoke by declaring it in a single
configuration entry (name, address space, options), so that when the
deployment pipeline runs, the new spoke is fully wired into the hub —
peered with gateway transit, linked to all hub-managed private DNS zones,
and reachable from the VPN — without any manual portal steps and without
touching the definition of existing spokes.

**Why this priority**: This is the core value proposition of the platform.
The whole point is that future demos do not require re-implementing
networking. If this scenario is broken or laborious, the platform fails its
purpose.

**Independent Test**: Testable after User Story 1 completes. The operator
adds a second spoke entry in the configuration file, opens a PR, merges
it, and after the pipeline finishes connects to the VPN (or uses an
already-open VPN session) and confirms that resources placed into the new
spoke are resolvable and reachable on their private IPs — with no portal
operations and no edits to the first spoke's configuration.

**Acceptance Scenarios**:

1. **Given** the platform is already deployed with one spoke, **When** the
   operator adds one new spoke entry to the configuration and merges the
   PR, **Then** the pipeline provisions a new VNet, the bidirectional
   peering with the hub (with gateway transit and remote-gateway use), and
   the private DNS zone links — without modifying any resource belonging
   to the existing spoke.
2. **Given** a new spoke has been added with one or more services that
   register into a hub-managed private DNS zone, **When** the operator
   queries those names from the VPN client, **Then** resolution returns
   the spoke-side private IPs and a session on the relevant port succeeds.
3. **Given** the operator submits a configuration entry whose address
   space overlaps with the hub VNet, the VPN client address pool, or any
   existing spoke, **When** the pipeline runs, **Then** the change is
   rejected (either at plan time or before apply) with an error that
   identifies the overlap.

---

### User Story 3 - Reproducible teardown and redeployment (Priority: P2)

As the operator, I want to be able to destroy the entire platform and
redeploy it from the same configuration so that I can recover from drift,
mistakes, or extended idle periods without leftover resources or manual
cleanup.

**Why this priority**: Important for sustainability of a personal lab
(cost recovery during long idle windows, recovery from experimentation
gone wrong) but not required for the first useful deployment.

**Independent Test**: Run the documented teardown procedure; confirm no
in-scope resources remain in the subscription. Then run the deployment
pipeline on the same configuration; confirm User Story 1 still passes
end-to-end.

**Acceptance Scenarios**:

1. **Given** a fully deployed platform, **When** the operator triggers the
   documented teardown procedure, **Then** every in-scope resource is
   removed and no orphaned resources remain.
2. **Given** the platform has been torn down, **When** the deployment
   pipeline runs against the unchanged configuration, **Then** the
   platform returns to the same observable state as User Story 1's
   completion.

---

### Edge Cases

- **VPN gateway provisioning latency**: Initial provisioning of the VPN
  gateway can take 30–45 minutes. The deployment pipeline must treat this
  as expected behavior, not as failure.
- **Operator not authorized for VPN**: If the connecting user is not in
  the Entra group authorized for VPN access, the connection attempt must
  fail with a clear authorization error rather than appear to succeed and
  then silently fail to route.
- **DNS forwarder unreachable from VPN client**: If the inbound DNS
  endpoint IP is not delivered to the VPN client through the VPN profile,
  name resolution will fail on the client side; the platform must arrange
  for the VPN profile to advertise the correct DNS server(s).
- **Spoke address-space collision**: A proposed spoke must not overlap
  with the hub VNet, the VPN client address pool, or any already-deployed
  spoke. Overlap must be caught before apply.
- **Spoke name collision**: Two spoke entries with the same logical name
  must be rejected at validation time.
- **Removing a spoke**: Deleting a spoke entry from configuration must
  cleanly remove the spoke VNet, peerings, and DNS zone links, without
  affecting other spokes or the hub.
- **Private DNS zone already linked elsewhere**: If a hub-managed private
  DNS zone is already linked (via an out-of-band action) to a VNet not
  owned by this platform, the next apply must not silently break that
  link; conflicts must surface as errors.
- **State backend unavailable**: If the IaC state backend is unreachable
  or the pipeline identity has lost permission, the pipeline must fail
  fast with an actionable message rather than attempt a local fallback.
- **OIDC trust mis-scoped**: If the GitHub Actions federated identity
  cannot acquire a token for the target subscription, the pipeline must
  fail before any change is attempted.
- **Identity bootstrap precedes IaC**: The Azure identity that GitHub
  Actions uses for deployment, its federated credential, and the role
  assignments required to read the IaC state backend and write to the
  target subscription must exist before the first pipeline run. This
  bootstrap is performed once by the operator (with agent assistance) and
  is out of scope for the per-deployment pipeline itself.

## Requirements *(mandatory)*

### Functional Requirements

**Topology and connectivity**

- **FR-001**: The platform MUST provision a single hub virtual network
  in one Azure region. The hub's target subscription ID and resource
  group name are bootstrap inputs supplied by the operator. The
  platform MUST create the hub resource group (it MUST NOT assume one
  pre-exists). All hub resources MUST live in that resource group.
- **FR-001a**: Each spoke configuration entry MUST declare its own
  target subscription ID, resource group name, address space, and
  logical name. Spokes MAY live in any subscription the operator owns,
  including subscriptions different from the hub's. The platform MUST
  create each spoke's resource group in the declared subscription. All
  resources belonging to one spoke MUST live in that single resource
  group; no spoke resources may be placed in the hub resource group or
  in any other spoke's resource group.
- **FR-002**: The hub MUST host the P2S VPN gateway and all centrally
  shared private DNS resources.
- **FR-003**: Each spoke MUST be a separate virtual network peered
  bidirectionally with the hub, configured so that the spoke uses the
  hub's gateway (gateway transit on the hub side, use-remote-gateway on
  the spoke side). Cross-subscription peerings between spoke and hub
  MUST be supported when the spoke and hub live in different
  subscriptions.
- **FR-004**: VPN clients MUST be able to reach resources by private IP
  in the hub and in every deployed spoke; spoke-to-spoke traffic is out
  of scope for this release but the routing model MUST NOT
  architecturally preclude enabling it later.
- **FR-004a**: Each spoke MUST be provisioned with a platform-managed
  network security group on its workload subnet whose only inbound rule
  permits all traffic originating from the VPN client address pool;
  all other inbound traffic MUST be denied. The hub's shared subnets
  MUST follow the same default. Spoke configuration entries MUST NOT be
  required to declare exposed service ports.

**Name resolution**

- **FR-005**: From a connected VPN client, the operator MUST be able to
  resolve the private DNS names of resources in the hub and in every
  spoke without any manual client-side DNS configuration beyond what the
  VPN profile delivers.
- **FR-006**: All private DNS zones (including Azure Private Link zones
  for the services the operator plans to consume from spokes) MUST be
  owned in the hub and linked to every spoke that needs them.
- **FR-007**: To satisfy FR-005, the VPN client profile MUST advertise
  DNS server addresses that are themselves reachable over the VPN tunnel
  and that can resolve every hub-owned private DNS zone.
- **FR-007a**: The VPN tunnel MUST operate in split-tunnel mode. The VPN
  profile MUST advertise only the hub VNet CIDR, every deployed spoke
  VNet CIDR, and the inbound DNS resolver IP as routed prefixes; all
  other client traffic MUST bypass the tunnel. The gateway-side
  configuration MUST update automatically when spokes are added or
  removed (profile re-download via the portal may be required after
  the routed-prefix list changes).

**Adding and removing spokes**

- **FR-008**: Adding a new spoke MUST require editing a single
  configuration surface (e.g., one map/list entry) and MUST NOT require
  editing the configuration of any existing spoke.
- **FR-009**: After a configuration-only spoke addition is merged and the
  pipeline runs, the new spoke's peering, DNS zone links, and VPN
  reachability MUST be in place with no manual portal action.
- **FR-010**: Removing a spoke MUST be a single configuration deletion
  that cleanly destroys the spoke VNet, peerings, and DNS zone links.

**Validation**

- **FR-011**: The platform MUST validate, prior to apply, that no spoke
  address space overlaps with the hub VNet, the VPN client address pool,
  or any other already-declared spoke. This validation MUST consider
  address spaces across all subscriptions in the spoke inventory, not
  only those in the same subscription as the spoke being added.
- **FR-012**: The platform MUST reject spoke names and spoke resource
  group names that are not unique within the deployment (uniqueness
  applies across the entire spoke inventory, not per subscription).

**Identity and authentication**

- **FR-013**: GitHub Actions MUST authenticate to Azure via Entra ID
  workload identity federation (OIDC). No client secrets, certificates,
  or other long-lived credentials may be created, stored, or used.
- **FR-014**: The IaC state backend MUST be accessed using the same
  federated identity (or another Entra-bound identity), never using
  storage account access keys or SAS tokens. The state account is a
  pre-existing resource whose subscription, resource group, account
  name, and container are bootstrap inputs; the platform MUST NOT
  assume the state account lives in the same subscription as the
  deployed platform resources.
- **FR-015**: P2S VPN authentication MUST use Entra ID; pre-shared keys,
  certificates issued from a local root, and other non-Entra mechanisms
  MUST NOT be used.
- **FR-016**: VPN access MUST be gated on membership in a designated
  Entra group; the operator's individual Entra account is added to that
  group rather than authorized directly. The group is created once
  during bootstrap and its object ID is supplied to the pipeline as an
  input. The deployment identity MUST NOT be granted Microsoft Graph
  permissions to create, modify, or enumerate Entra groups; group
  membership is managed by the operator out-of-band.
- **FR-016a**: Interactive access to the validation workload's virtual
  machine MUST use Microsoft Entra ID login (the Azure AD login VM
  extension on Linux).
  Access MUST be gated by Azure RBAC (`Virtual Machine User Login` for
  standard access, `Virtual Machine Administrator Login` for elevated
  access) assigned to Entra principals. No SSH keys, no local Linux
  accounts with passwords, and no Bastion host may be provisioned for
  this purpose.

**Identity bootstrap (one-time, out-of-pipeline)**

- **FR-017**: As a one-time bootstrap (performed by the agent, not the
  operator), the deployment identity used by GitHub Actions and its
  federated credential mapping to the appropriate repository and
  branch/environment MUST be established before the first pipeline run.
  The bootstrap MUST: (i) enumerate every subscription the operator
  owns (e.g., via `az account list`), (ii) assign the deployment
  identity both **Contributor** and **User Access Administrator** at
  subscription scope on every enumerated subscription, (iii) assign
  the deployment identity **Storage Blob Data Contributor** on the
  existing state storage account (whichever subscription it lives in),
  and (iv) create the VPN access Entra group (per FR-016) using the
  operator's interactive Entra session and capture its object ID as a
  pipeline input. The operator supplies only: the hub's target subscription ID
  and resource group name, the existing state backend coordinates
  (state subscription ID, resource group, storage account name,
  container name), and the GitHub repository / branch / environment
  scoping for the federated credential. The bootstrap MUST NOT create
  any long-lived secret on either side of the trust.
- **FR-017a**: When the operator later adds a new subscription to their
  Entra tenant, a one-time re-run of the bootstrap (or its incremental
  equivalent) MUST extend the deployment identity's Contributor and
  User Access Administrator assignments to the new subscription before
  any spoke can be declared there.

**Pipeline and reproducibility**

- **FR-018**: All infrastructure MUST be defined as code in the
  repository; no resource managed by this platform may be created or
  modified through the portal or CLI outside the pipeline.
- **FR-019**: The deployment pipeline MUST run a non-mutating plan on
  pull requests and only apply changes when a PR is merged to the
  default branch.
- **FR-020**: The plan output MUST be surfaced for human review on the PR
  before merge, and the apply step MUST consume the plan artifact
  produced by the PR build.
- **FR-021**: Pipeline runs MUST be deterministic with respect to
  provider and module versions (versions pinned in the repository).

**Cost posture**

- **FR-022**: The hub MUST use the lowest VPN gateway SKU compatible
  with Entra-authenticated P2S VPN access.
- **FR-023**: No Network Virtual Appliance, Azure Firewall, or premium
  Application Gateway / WAF tier is included in this release.

**Observability**

- **FR-024**: The hub MUST contain exactly one Log Analytics workspace
  used as the platform's diagnostic sink. Diagnostic settings MUST be
  configured on the P2S VPN gateway and on the DNS Private Resolver,
  routing their logs and metrics to this workspace. No other
  platform-managed diagnostic settings are deployed by default; in
  particular, NSG flow logs are NOT enabled by the platform.
- **FR-025**: The Log Analytics workspace MUST use the lowest-cost
  configuration that supports the required diagnostic categories
  (default pricing tier, shortest retention compatible with the
  operator's needs — 30 days unless otherwise specified).

### Key Entities *(include if feature involves data)*

- **Hub VNet**: The central virtual network. Owns the VPN gateway, the
  inbound DNS endpoint that VPN clients resolve through, and the links
  for every centrally managed private DNS zone.
- **Spoke VNet**: An independent virtual network for one demo workload,
  peered bidirectionally with the hub with gateway transit and linked to
  the hub's private DNS zones.
- **Spoke configuration entry**: A single declarative record describing
  one spoke. Required fields: logical name (unique across the
  inventory), target subscription ID, target resource group name
  (unique across the inventory; the platform creates this RG), VNet
  address space. Optional fields: any flags such as which optional
  hub-managed DNS zones to link, additional subnet definitions, etc.
  The set of these records is the platform's inventory of spokes.
- **Centrally managed private DNS zone**: A private DNS zone (custom or
  Azure Private Link) owned in the hub and linked to spokes that need it,
  so that names registered in spokes resolve consistently across the
  platform.
- **VPN client address pool**: The IP range from which connected VPN
  clients receive their tunnel-side address. Must not overlap with the
  hub or any spoke.
- **VPN access group**: An Entra ID group whose members are authorized to
  establish a P2S VPN session. Created once during bootstrap and
  referenced by the pipeline via its object ID; membership is managed
  by the operator out-of-band.
- **Deployment identity**: The Entra-bound identity that GitHub Actions
  uses to authenticate to Azure via OIDC for both state access and
  resource deployment.
- **Validation workload**: A small resource set provisioned in the
  initial spoke that the operator targets to validate both private DNS
  resolution and private-IP connectivity over the VPN.
- **Platform diagnostic sink**: A single Log Analytics workspace in the
  hub that receives diagnostic data from the P2S VPN gateway and the
  DNS Private Resolver.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a clean clone of the repository and a one-time
  identity bootstrap, the operator reaches a working VPN connection with
  validated DNS and connectivity to the initial spoke in a single
  pipeline run, with no manual portal steps after the bootstrap.
- **SC-002**: Adding a new spoke is a single-file configuration change
  that takes the operator less than five minutes of authoring time
  (excluding pipeline plan/apply duration), and the resulting PR diff
  touches only the spoke inventory entry plus any auto-generated lock or
  plan artifacts — not the definition of any existing spoke.
- **SC-003**: After merging a new-spoke PR, the new spoke is reachable
  by private IP and resolvable by private DNS from a connected VPN
  client on the operator's first attempt, with no client-side changes.
- **SC-004**: A configuration that introduces an address-space overlap or
  duplicate spoke name is rejected before any cloud-side change is
  attempted, with an error message that identifies the conflicting
  entries.
- **SC-005**: A scan of the repository, the deployed environment, and
  the pipeline configuration finds zero long-lived secrets
  (no shared keys, no SAS tokens, no client secrets, no pre-shared
  keys); every authentication path is Entra-bound.
- **SC-006**: The platform can be torn down and redeployed from the same
  configuration with the same end-to-end behavior (SC-001 still passes
  after a destroy/redeploy cycle).
- **SC-007**: The steady-state monthly cost of the hub at the chosen
  minimum SKUs is documented in the repository and is reviewed on every
  PR that adds a new always-on resource.

## Assumptions

- The platform spans multiple Azure subscriptions within a single Entra
  tenant. The hub lives in one operator-supplied subscription; each
  spoke independently targets a subscription declared in its
  configuration entry. The state storage account may be in yet another
  subscription. See FR-001, FR-001a, FR-014, and FR-017.
- Exactly one Azure region is used; multi-region is out of scope.
- The IaC state backend (Storage account, container, resource group, and
  subscription) already exists. The operator supplies its coordinates to
  the agent during bootstrap.
- The operator has, or can obtain, sufficient Entra privileges to create
  the deployment identity, the VPN access group, and the necessary role
  assignments during the one-time bootstrap.
- The VPN client tool used is the Entra-aware Azure VPN client (this is
  the only client that supports Entra-authenticated P2S VPN).
- The initial validation workload is a small Linux virtual machine
  (with the Azure AD login extension installed; see FR-016a) plus a
  storage account whose blob service is exposed via a private endpoint
  into the validation spoke. Together these exercise both raw
  private-IP connectivity (`az ssh vm` to the VM, authenticated via
  Entra) and Azure Private Link DNS auto-registration (resolving the
  storage private endpoint name from the VPN client).
- Default address allocation (operator may override in configuration):
  hub `10.0.0.0/22`, VPN client address pool `10.255.0.0/16`, initial
  spoke `10.1.0.0/22`. Each subsequent spoke takes the next available
  `/22` from `10.x.0.0/22` (x ≥ 2).
- The platform is single-tenant to the operator's Entra tenant; no
  guest-account or cross-tenant access is supported.
- Spokes target subscriptions by referencing a named "slot"; the
  slot-to-subscription mapping is supplied at bootstrap time and is
  the only place subscription identifiers appear in operator-facing
  configuration. The mechanism behind slots (one provider alias per
  slot) is an implementation detail of the IaC tool and is documented
  in `plan.md` / `data-model.md`.
- Compliance with the project constitution is assumed (in particular:
  OpenTofu as the IaC tool, Azure Verified Modules as the default
  module source, no NVAs, secretless Entra auth).
