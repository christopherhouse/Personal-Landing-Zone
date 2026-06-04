# Bootstrap

This directory contains the **one-time, idempotent bootstrap** that prepares an
Entra tenant + a set of Azure subscriptions to host the Hub-and-Spoke
Networking Foundation. After this runs once, every subsequent change goes
through the PR + apply pipeline; the operator never re-runs this script except
when a brand-new subscription is added to the tenant.

The authoritative contract for inputs, outputs, and Azure-side actions is
[`../specs/001-hub-spoke-foundation/contracts/bootstrap-inputs.md`](../specs/001-hub-spoke-foundation/contracts/bootstrap-inputs.md).
Read it before running the script.

## When to run

| Scenario                                                    | Action                                                         |
| ----------------------------------------------------------- | -------------------------------------------------------------- |
| First-time setup in a fresh tenant                          | Run end-to-end with all parameters supplied.                   |
| New subscription added to the tenant after initial bootstrap | Re-run with the same parameters; the script creates the new slot's role assignments and updates `outputs/discovered.auto.tfvars.json`. You then add a matching `provider "azurerm" { alias = "sub_<slot>" }` block to `infra/providers.tf` (one-time HCL edit per new subscription). |
| Federated credential needs to be added for a new branch/env | Re-run with `-GithubBranchOrEnvironment` extended.             |
| Anything else                                               | Do **not** re-run the bootstrap. Use PRs.                      |

Re-runs are safe: every Azure-side action checks current state before
mutating. The output `bootstrap-report.md` distinguishes `[created]` from
`[exists]` for every object.

## Input categories

Inputs fall into four buckets — the script enforces this structure:

1. **Operator-supplied (always required)** — IDs and names only the operator
   knows. Tenant ID, hub subscription ID, hub RG name, state account
   coordinates, GitHub repo and credential scopes.
2. **Auto-discovered (do not pass; the script computes them)** — the full set
   of subscription slots in the tenant (via `az account list`), and the
   service principal / Entra group object IDs after creation.
3. **Defaults (override only if you need to)** — display names for the
   deployment app and VPN access group, and the default region.
4. **Optional (don't bother on first run)** — anything the script does not
   currently accept.

The full parameter table lives in [`bootstrap-inputs.md`](../specs/001-hub-spoke-foundation/contracts/bootstrap-inputs.md);
this README intentionally does not duplicate it.

## Re-run semantics

- Running with the same inputs is a no-op.
- Running after a new subscription appears creates the two RBAC entries on it
  (Contributor + User Access Administrator on the deployment SP), adds it to
  `discovered.auto.tfvars.json`, and prints a reminder to add the matching
  provider alias.
- Running after a subscription is deleted leaves the historical role
  assignments orphaned; Azure auto-purges them within ~30 days. The script
  logs the situation but does not error.

## Outputs

Written to `outputs/`. Both files are normally git-ignored but `T049` in
[`../specs/001-hub-spoke-foundation/tasks.md`](../specs/001-hub-spoke-foundation/tasks.md)
calls for committing `discovered.auto.tfvars.json` on the initial deployment
branch so the pipeline can consume it.

- `discovered.auto.tfvars.json` — slot map + Entra object IDs; consumed
  automatically by `tofu plan` because of the `.auto.tfvars.json` suffix.
- `bootstrap-report.md` — human-readable summary the operator reviews before
  committing. Lists every created vs. existing object, every role assignment,
  every federated credential, the state-account coordinates, and the
  repository Variables the operator must configure in GitHub Actions.

## Prerequisites

- Azure CLI `>= 2.62` on `PATH`.
- The operator is signed in via `az login --tenant <TenantId>` with at least:
  - `Application Administrator` (or `Cloud Application Administrator`) in
    Entra (for app/SP/federated-credential/group creation).
  - `User Access Administrator` (or `Owner`) on every subscription that will
    receive a slot (for the SP role assignments).
- PowerShell 7+ (`pwsh`) — the script uses cross-version cmdlets but is
  developed and tested on Windows 11.

## Invocation

```powershell
pwsh -File bootstrap/bootstrap.ps1 `
    -TenantId                  '00000000-0000-0000-0000-000000000000' `
    -HubSubscriptionId         '11111111-1111-1111-1111-111111111111' `
    -HubResourceGroupName      'rg-plz-hub-eastus2' `
    -StateSubscriptionId       '11111111-1111-1111-1111-111111111111' `
    -StateResourceGroupName    'rg-tfstate' `
    -StateStorageAccountName   'sttfstateplz' `
    -StateContainerName        'tfstate' `
    -GithubRepository          '<owner>/personal-landing-zone' `
    -GithubBranchOrEnvironment 'branch:main', 'pull_request'
```

The script's only output to the terminal is a progress log; the substance is
in `outputs/bootstrap-report.md` and `outputs/discovered.auto.tfvars.json`.

## After bootstrap

1. Open `outputs/bootstrap-report.md` and confirm everything created is what
   you expected.
2. In GitHub, set the repository **Variables** listed at the bottom of the
   report. No Secrets are required (Constitution Principle III).
3. Add the operator's Entra user (and any other VPN users) to the VPN access
   group named in the report.
4. On a fresh feature branch, commit `outputs/discovered.auto.tfvars.json`.
5. Open the initial deployment PR. The `plan.yml` workflow runs; merging it
   triggers the first `apply.yml` run (~30-45 min, dominated by VPN gateway
   provisioning — see `specs/001-hub-spoke-foundation/quickstart.md` Part 1).
