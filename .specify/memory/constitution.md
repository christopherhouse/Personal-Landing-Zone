<!--
Sync Impact Report
==================
Version change: (initial) → 1.0.0
Bump rationale: First ratification of the project constitution; no prior version.

Modified principles: N/A (initial adoption)
Added sections:
  - Core Principles (I–V)
  - Technology Stack & Constraints
  - Development Workflow & Quality Gates
  - Governance

Removed sections: None.

Templates / artifacts requiring updates:
  - .specify/templates/plan-template.md  ⚠ pending — "Constitution Check" gate
    block is generic; future plans should reference Principles I–V explicitly.
    No structural change required now; flagged for first plan execution.
  - .specify/templates/spec-template.md  ✅ no change required (tech-agnostic).
  - .specify/templates/tasks-template.md ✅ no change required (illustrative
    sample tasks; real task lists will be generated per feature).
  - .specify/extensions/**, .specify/workflows/**          ✅ no change.
  - README.md / docs/quickstart.md                          ⚠ not yet authored;
    will be generated as part of the first feature plan.

Deferred / follow-up TODOs:
  - TODO(README): Author top-level README pointing to this constitution and
    the first feature plan once /speckit-specify produces it.
-->

# Personal Landing Zone Constitution

## Core Principles

### I. Azure Verified Modules First

All Azure resources MUST be provisioned via Azure Verified Modules (AVM) when a
suitable, published, non-deprecated AVM exists for the resource type. The
`azurerm` and `azapi` providers MAY be used directly only when (a) no AVM
covers the required resource, (b) the available AVM is in `preview` /
`experimental` status and blocks delivery, or (c) the AVM materially conflicts
with another non-negotiable principle (cost, secretless identity, or
extensibility). Every direct-provider use MUST be justified in the plan's
Complexity Tracking table and re-evaluated whenever AVM coverage changes.

**Rationale**: AVM encodes Microsoft's reviewed defaults for security,
diagnostics, and naming, which materially reduces the surface area a personal
lab owner must audit on their own.

### II. Cost-Optimized Minimal Footprint (NON-NEGOTIABLE)

This is a personal lab. Every resource MUST be deployed at the lowest SKU that
satisfies the functional requirement. The P2S VPN gateway MUST use the
minimum supported SKU (`VpnGw1` / Basic where the scenario allows). Network
Virtual Appliances (NVAs), Azure Firewall, Application Gateway WAF tier, and
other premium hub services MUST NOT be deployed. Idle-cost resources (e.g.,
always-on gateways) MUST be documented in the plan's cost section with an
estimated monthly burn.

**Rationale**: Cost overruns are the single most common reason personal cloud
labs are abandoned. Forcing the minimum SKU and an explicit cost line item
keeps the environment sustainable.

### III. Secretless Entra Authentication

No long-lived secrets — access keys, SAS tokens, connection strings, service
principal client secrets, or shared keys — MAY be created, stored, or
referenced by this codebase, its state, or its CI/CD. All authentication MUST
use Microsoft Entra ID: GitHub Actions to Azure via OIDC federated identity
credentials; resource-to-resource calls via managed identities; human access
via Entra ID accounts and groups. Azure RBAC MUST be assigned to Entra
identities (users, groups, managed identities), never to keys. Resources that
expose a local-auth/shared-key surface (e.g., storage accounts, Cosmos DB,
Service Bus) MUST disable it when the resource type supports doing so.

**Rationale**: A personal lab is a prime target for accidental secret leakage
(committed `.tfvars`, screenshots, logs). Removing the option eliminates the
class of incident entirely.

### IV. Hub-and-Spoke Extensibility

The hub MUST be designed so that adding spokes, enabling spoke-to-spoke
transit, and introducing a future inspection point are configuration changes,
not redesigns. Concretely: VNet address spaces MUST be allocated from a
documented, non-overlapping plan with room for at least four additional
spokes; hub/spoke peerings MUST be parameterized; private DNS zones MUST be
hub-resourced and linked to spokes via module inputs (not hard-coded); and
routing MUST flow through a hub construct (route tables and/or a placeholder
for a future gateway/firewall) rather than direct spoke-to-spoke peering.
Spoke-to-spoke traffic is OUT OF SCOPE for v1 but MUST NOT be architecturally
precluded.

**Rationale**: The user has explicitly stated future intent to test
spoke-to-spoke and broader private-networking scenarios. A design that can
absorb those changes via variables avoids a costly rewrite.

### V. IaC Quality, Reproducibility, and Automated Delivery

All infrastructure MUST be defined in OpenTofu (`tofu`) with state stored in
the pre-existing Azure Storage account via the `azurerm` backend, using OIDC
auth — never access keys. Code MUST pass `tofu fmt -check`, `tofu validate`,
and a static analysis pass (e.g., `tflint` with the Azure ruleset and
`trivy config` or `checkov`) before merge. Provider and module versions MUST
be pinned (`required_providers` with `~>` constraints; AVM module versions
pinned to a tag). Every change MUST flow through a GitHub Actions pipeline
that runs plan on pull request and apply on merge to the default branch; no
manual `tofu apply` against the shared state from a developer workstation.

**Rationale**: Personal projects rot fastest when local applies diverge from
the repo. Hard-pinning the pipeline as the only writer keeps state and code
in sync and makes the project resumable months later.

## Technology Stack & Constraints

- **IaC tool**: OpenTofu (latest stable minor; version pinned in
  `.tool-versions` / workflow). Terraform CLI MUST NOT be used.
- **Providers**: `hashicorp/azurerm` and `Azure/azapi`, both version-pinned.
- **Modules**: Azure Verified Modules from the public registry, tag-pinned.
- **State**: Existing Azure Storage account, `azurerm` backend, OIDC auth,
  per-environment state file naming; soft-delete and versioning on the
  state container MUST remain enabled.
- **CI/CD**: GitHub Actions, federated credentials per environment, branch
  protection requiring plan + checks to pass before merge.
- **Networking baseline**: Single hub VNet with GatewaySubnet, P2S VPN
  Gateway (minimum SKU), Azure DNS Private Resolver (inbound endpoint at
  minimum; outbound endpoint only if a forwarding scenario requires it),
  Private DNS zones for the Azure services consumed in spokes (e.g.,
  `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`,
  etc.). Spokes consume hub DNS via VNet links.
- **Forbidden**: NVAs, Azure Firewall, premium WAF/App Gateway tiers,
  long-lived secrets in code or pipeline.

## Development Workflow & Quality Gates

1. **Branching**: Feature branches via `/speckit-specify` (the
   `speckit.git.feature` hook). No direct commits to the default branch.
2. **Specification → Plan → Tasks**: Every change of architectural
   significance MUST flow through `/speckit-specify`, `/speckit-plan`,
   `/speckit-tasks`. Bug fixes and trivial parameter tweaks MAY skip the
   spec but MUST still go through PR review.
3. **Pre-merge gates**: `tofu fmt -check`, `tofu validate`,
   `tofu plan` (against the target environment), `tflint`, and a
   security scan (`trivy config` or equivalent). All gates MUST pass.
4. **Plan review**: The PR description MUST include the `tofu plan`
   summary (resources to add/change/destroy) and an explicit acknowledgment
   line for any destructive operations.
5. **Apply**: Only the GitHub Actions workflow on the default branch MAY
   run `tofu apply`. Apply MUST consume the exact plan artifact produced
   by the PR pipeline (`-out=tfplan` → upload → download → apply).
6. **Cost check**: Each plan MUST be reviewed against the cost-minimization
   principle; any new resource that adds non-trivial idle cost MUST be
   called out in the PR description.

## Governance

This constitution supersedes other process documents in this repository.
Any conflict between this document and ad-hoc guidance is resolved in favor
of this document.

- **Amendments**: Proposed via PR that modifies
  `.specify/memory/constitution.md` and increments the version per semver:
  MAJOR for removal or backward-incompatible redefinition of a principle;
  MINOR for a new principle or materially expanded guidance; PATCH for
  clarifications and wording fixes.
- **Compliance review**: Each `/speckit-plan` execution MUST evaluate the
  feature against Principles I–V in its Constitution Check section.
  Violations MUST be either resolved or recorded with justification in the
  plan's Complexity Tracking table.
- **Drift audit**: Any direct-provider resource introduced under Principle
  I's escape hatch MUST be reviewed at least once per amendment cycle to
  confirm no AVM has since become viable.
- **Runtime guidance**: Day-to-day coding conventions live in `CLAUDE.md`
  (project root) and supersede style preferences not codified here.

**Version**: 1.0.0 | **Ratified**: 2026-06-04 | **Last Amended**: 2026-06-04
