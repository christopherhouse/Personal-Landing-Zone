# Quickstart: End-to-End Validation of the Hub-and-Spoke Foundation

**Branch**: `001-hub-spoke-foundation` | **Date**: 2026-06-04

This guide is the authoritative acceptance test for User Story 1 (first-time deployment) and User Story 2 (configuration-only spoke addition). It assumes the bootstrap step has already run successfully (see [`contracts/bootstrap-inputs.md`](./contracts/bootstrap-inputs.md)).

## Prerequisites

On the operator's workstation (Windows 11):

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.62
- [Azure VPN Client for Windows](https://learn.microsoft.com/azure/vpn-gateway/point-to-site-entra-vpn-client-windows) (Microsoft Store)
- [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.9 (only needed for local plan testing; the pipeline does real planning and applying)
- `az ssh` extension: `az extension add --name ssh`

Operator's Entra account membership:

- Member of the `sg-plz-vpn-users` group (added by the operator out-of-band after bootstrap; see [`bootstrap-inputs.md`](./contracts/bootstrap-inputs.md)).
- The operator's Entra user has been granted `Virtual Machine User Login` on the validation VM and `Storage Blob Data Reader` on the validation storage account. (These role assignments are platform-managed and granted to the `sg-plz-vpn-users` group, so being in the group is sufficient.)

GitHub repo state:

- The default branch has the initial spoke configuration committed (`config/platform.auto.tfvars`, `config/subscriptions.auto.tfvars`, `config/spokes.auto.tfvars` with the `validation` spoke).
- Repository Variables set per the bootstrap script's emitted summary.
- The most recent `apply.yml` workflow run completed successfully.

## Part 1 — Initial deployment validation (User Story 1)

### Step 1.1: Confirm the apply finished cleanly

1. Open the GitHub Actions tab on the repository.
2. Find the most recent `apply.yml` run on the default branch.
3. Confirm: status = `success`, and the `tofu apply tfplan` step exit code is `0`.

If the apply is still running (initial VPN gateway provisioning takes 30–45 minutes), wait. This is expected behavior, not a failure (Edge Cases: "VPN gateway provisioning latency").

### Step 1.2: Download the VPN client profile

1. In the Azure portal, navigate to the VPN gateway: `vgw-plz-hub` in the `rg-plz-hub-eastus2` resource group.
2. **Point-to-site configuration** → **Download VPN client**.
3. Unzip the download. Locate `AzureVPN/azurevpnconfig_aad.xml`.

### Step 1.3: Import the profile and connect

1. Open the Azure VPN Client.
2. **Import** → select `azurevpnconfig_aad.xml`.
3. Select the imported profile → **Connect**.
4. Sign in with the operator's Entra account when prompted.

**Expected**: Connection established within ~10 seconds; no prompt for a pre-shared key or certificate (FR-015).

**Failure path — operator not in the VPN access group**: Azure returns an authorization error message ("user is not authorized to access this VPN"). The operator must be added to `sg-plz-vpn-users` and re-attempt. (Edge Cases: "Operator not authorized for VPN".)

### Step 1.4: Verify DNS resolution over the VPN

In an elevated PowerShell prompt:

```powershell
# Resolves to the inbound DNS resolver IP (e.g., 10.0.3.4) — pushed by the VPN profile.
Get-DnsClient | Where-Object { $_.InterfaceAlias -like '*VPN*' } | Get-DnsClientServerAddress

# Resolve the validation storage account's blob private endpoint name.
nslookup $env:STVAL_PE_NAME    # e.g., stplzval4f3a.blob.core.windows.net
# Expected: returns a private IP in the validation spoke (10.1.0.x).

# Resolve the validation VM by its auto-registered A record (if applicable).
nslookup vm-plz-validation.plz.internal
# Expected: returns a private IP in the validation spoke.
```

**Expected**: Both names resolve to private IPs within `10.1.0.0/22`. Public IPs or NXDOMAIN indicate the VPN profile is not pointing at the resolver (Edge Cases: "DNS forwarder unreachable from VPN client"). Disconnect and re-import the VPN profile.

### Step 1.5: SSH to the validation VM via Entra

```powershell
az login --tenant <tenant-id>
az ssh vm --resource-group rg-plz-spoke-validation-eastus2 --name vm-plz-validation
```

**Expected**: An interactive shell on the VM, opened in under ten seconds (Acceptance Scenario US1.4). No password prompt, no SSH-key prompt — auth flowed through Entra.

Once on the VM:

```bash
# Confirm the VM can resolve the storage PE from inside the spoke.
nslookup $STVAL_PE_NAME

# Confirm DNS is going through the resolver (the spoke's DNS server should be the resolver IP via Azure-provided + VNet link).
cat /etc/resolv.conf
```

### Step 1.6: Exercise the private endpoint (blob plane)

Back on the operator's workstation, while still connected to the VPN:

```powershell
az storage blob list `
    --account-name $env:STVAL_ACCOUNT_NAME `
    --container-name validation `
    --auth-mode login
```

**Expected**: The command returns successfully (an empty list is fine on first run). The traffic flows: workstation → VPN → hub → spoke peering → storage PE → blob endpoint, with auth via Entra OAuth (no account key).

### Step 1.7: Disconnect and re-validate cost posture

1. Disconnect the VPN.
2. In the Azure portal, browse to `Cost Management + Billing` → `Cost analysis` scoped to the hub subscription.
3. Confirm the projected monthly cost for the `rg-plz-hub-eastus2` and `rg-plz-spoke-validation-eastus2` resource groups together is within the budget recorded in `docs/cost-baseline.md` (≤ $350/month at writing).

**User Story 1 passes** when steps 1.1 – 1.7 complete without errors.

## Part 2 — Configuration-only spoke addition validation (User Story 2)

### Step 2.1: Edit the spokes inventory

In a feature branch, edit `config/spokes.auto.tfvars` to add one new entry. Use a free `/22` slot:

```hcl
spokes = {
  validation = { ... }              # unchanged
  smoketest = {
    subscription_slot     = "hub"   # same sub as the hub — no new provider alias needed
    resource_group_name   = "rg-plz-spoke-smoketest-eastus2"
    address_space         = "10.2.0.0/22"
    workload_subnet_prefix = "10.2.0.0/24"
  }
}
```

**Expected**: The diff touches only this file. `config/subscriptions.auto.tfvars` and `infra/providers.tf` remain unchanged (Acceptance Scenario US2.1).

### Step 2.2: Open the PR and review the plan

Push and open a PR. The `plan.yml` workflow runs.

**Expected**:

- All static checks pass (`fmt-check`, `validate`, `tflint`, `trivy-config`).
- The PR receives a comment with the `tofu plan` diff.
- Plan summary shows resources to add (~6: RG, VNet, NSG + association, two peerings, all DNS zone links) and zero resources to destroy or replace.
- No changes touch the `validation` spoke's resources (FR-008 second clause).

### Step 2.3: Merge and watch the apply

Merge the PR. The `apply.yml` workflow runs.

**Expected**: `tofu apply tfplan` completes successfully in under 10 minutes (`plan.md` Performance Goals).

### Step 2.4: Verify the new spoke is reachable

With an active VPN session (refresh the profile if the route list needs updating — re-download from the portal if `route print` does not show `10.2.0.0/22`):

```powershell
# DNS — the new spoke has no resources yet, but private DNS resolution for the linked zones still works.
nslookup $env:STVAL_PE_NAME
# Should still resolve, unchanged.

# Routing — the operator can ping the gateway-facing side of the new spoke (no resource at that IP yet,
# but the route exists and the peering is healthy).
route print | findstr 10.2.0.0
# Expected: a route entry for 10.2.0.0/22 via the VPN interface.
```

(Future demo workloads placed in the smoketest spoke can be reached just like the validation VM.)

**User Story 2 passes** when steps 2.1 – 2.4 complete without errors and the smoketest spoke is route-reachable from the VPN.

## Part 3 — Negative tests (validation behavior, FR-011 / FR-012)

These are recommended one-time sanity checks the operator can run on a feature branch (never merging the PR):

### 3.1 Address-space overlap

In `config/spokes.auto.tfvars`, set the `smoketest` spoke's `address_space` to `10.0.0.0/22` (the hub's space). Open a PR.

**Expected**: `plan.yml` job `validate` (or the plan job) fails with an error referencing `smoketest` and `hub` and the conflicting CIDRs (Acceptance Scenario US2.3).

### 3.2 Duplicate resource group name

In `config/spokes.auto.tfvars`, set `smoketest.resource_group_name` equal to `validation.resource_group_name`. Open a PR.

**Expected**: Plan halts with "resource group name not unique" naming both spokes.

### 3.3 Unknown subscription slot

In `config/spokes.auto.tfvars`, set `smoketest.subscription_slot = "ghost"`. Open a PR.

**Expected**: Plan halts with "Spoke 'smoketest' references unknown subscription slot 'ghost'. Add a provider alias and a subscription_slots entry first."

## Part 4 — Optional: teardown rehearsal (User Story 3)

> Skip unless you specifically want to validate SC-006.

1. From the default branch, run the `destroy.yml` workflow (manually triggered).
2. Confirm in the portal that `rg-plz-hub-eastus2` and `rg-plz-spoke-validation-eastus2` no longer exist.
3. Re-run `apply.yml` against the same configuration.
4. Repeat Part 1 from Step 1.2.

**Expected**: Part 1 still passes end-to-end. The platform is reproducible (SC-006).

## What to do when validation fails

- Capture the failing step's logs and the PR/run URL.
- Compare against the relevant Edge Case bullet in `spec.md`.
- For DNS-resolution failures, the most common culprit is a stale VPN profile after a config change that updated the routed-prefix list — re-download the profile from the portal (FR-007a notes).
- For SSH failures with "user is not authorized", verify membership in `sg-plz-vpn-users` (carries `Virtual Machine User Login` via the platform's role assignment).
