# `infra/` — OpenTofu Root

This directory is the single OpenTofu root for the Personal Landing Zone. It is composed of a small set of root files plus three child modules:

- `modules/hub/` — the shared services hub (VNet, P2S VPN gateway, DNS Private Resolver inbound endpoint, Private DNS zones, Log Analytics workspace).
- `modules/spoke/` — one peered workload VNet per logical spoke (RG, VNet, workload subnet, NSG, DNS zone links, bidirectional peering with the hub).
- `modules/workloads/validation/` — the validation workload (Linux VM with Entra SSH login + storage account with a blob private endpoint) layered into whichever spoke opts in via `include_validation_workload = true`.

Root files (`versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`) wire those modules together and consume configuration from `config/*.auto.tfvars`. Default and per-subscription-slot provider aliases live in `providers.tf`; the hub is invoked once and spokes via `for_each` across the `spokes` inventory.

For the full technical context — provider/module versions, address-space rules, bootstrap flow, and the validation procedure — see the active plan and its companion artifacts:

- Plan: [`../specs/001-hub-spoke-foundation/plan.md`](../specs/001-hub-spoke-foundation/plan.md)
- Spec: [`../specs/001-hub-spoke-foundation/spec.md`](../specs/001-hub-spoke-foundation/spec.md)
- Research decisions: [`../specs/001-hub-spoke-foundation/research.md`](../specs/001-hub-spoke-foundation/research.md)
- Variable / entity model: [`../specs/001-hub-spoke-foundation/data-model.md`](../specs/001-hub-spoke-foundation/data-model.md)
- Config contracts: [`../specs/001-hub-spoke-foundation/contracts/`](../specs/001-hub-spoke-foundation/contracts/)
- Validation procedure: [`../specs/001-hub-spoke-foundation/quickstart.md`](../specs/001-hub-spoke-foundation/quickstart.md)
- Constitution: [`../.specify/memory/constitution.md`](../.specify/memory/constitution.md)
