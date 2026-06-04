# Contract: `bootstrap/bootstrap.ps1` Inputs & Outputs

**Owner**: agent (run interactively by the operator's signed-in `az` session) | **Frequency**: once per Entra tenant, plus once per newly-introduced subscription.

This contract describes what the operator hands to the bootstrap script, what the script does in Azure, and what artifacts it leaves behind for the pipeline to consume.

## Operator-supplied inputs

| Input | Required | Source | Example |
|---|---|---|---|
| `-TenantId` | yes | operator | `00000000-0000-0000-0000-000000000000` |
| `-HubSubscriptionId` | yes | operator | The subscription that will host the hub resource group. |
| `-HubResourceGroupName` | yes | operator | `rg-plz-hub-eastus2` |
| `-StateSubscriptionId` | yes | operator | Subscription holding the existing TF state account. May equal `HubSubscriptionId` or differ. |
| `-StateResourceGroupName` | yes | operator | Existing RG containing the state storage account. |
| `-StateStorageAccountName` | yes | operator | Existing storage account. |
| `-StateContainerName` | yes | operator | Container inside the state account (created if missing — storage data-plane only). |
| `-GithubRepository` | yes | operator | `<owner>/<repo>` form. |
| `-GithubBranchOrEnvironment` | yes (repeatable) | operator | Each value becomes one federated credential. Examples: `branch:main`, `environment:prod`, `pull_request`. |
| `-DeploymentAppDisplayName` | no | default `app-plz-deploy` | Entra app display name. |
| `-VpnAccessGroupDisplayName` | no | default `sg-plz-vpn-users` | Entra group display name. |
| `-Region` | no | default `eastus2` | Used in resource names; not required for the SP/group creation itself. |

## Pre-flight checks

The script halts if any of:

1. `az` is not logged in OR is logged in to a different tenant than `-TenantId`.
2. The signed-in operator cannot `az ad app create` (i.e., lacks the Entra-side privileges to create apps / groups / federated credentials). The error message names the missing role(s).
3. Any of the `-State*` coordinates can't be read (`az storage account show`).
4. `Microsoft.Graph` not reachable.

## Azure-side actions (idempotent)

In order:

1. **Enumerate subs**: `az account list --query "[?tenantId=='<TenantId>']"`. Result becomes the canonical slot map; slot names are derived from each subscription's `name` field via `slugify(lowercase(name).replace(/[^a-z0-9]+/g, "_"))`, with the hub sub forced to slot name `hub`.
2. **Create deployment Entra application** (`az ad app create --display-name <DeploymentAppDisplayName>`), capture `appId` and `objectId`. Skip if an app with this display name already exists.
3. **Create the matching service principal** for the app. Skip if it already exists.
4. **Federated credentials**: for each `-GithubBranchOrEnvironment` value, create a federated credential on the app via `az ad app federated-credential create`. Idempotent on the credential's `name` field. Subject claim is mapped per [GitHub's documented format](https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims).
5. **Create the VPN access group**: `az ad group create --display-name <VpnAccessGroupDisplayName> --mail-nickname <sanitized>`. Skip if it exists.
6. **Per-subscription role assignments**:
   - `Contributor` at `/subscriptions/<id>` for the SP — `az role assignment create`.
   - `User Access Administrator` at `/subscriptions/<id>` for the SP.
   - Both idempotent on `(roleDefinitionName, principalId, scope)`.
7. **State-account data-plane role assignment**:
   - `Storage Blob Data Contributor` at `/subscriptions/<StateSubscriptionId>/resourceGroups/<StateResourceGroupName>/providers/Microsoft.Storage/storageAccounts/<StateStorageAccountName>` for the SP.
8. **Verify**: a final read-only pass that confirms every expected object exists with the expected scope/principal.

## Outputs

Written into `bootstrap/outputs/` (git-ignored):

### `discovered.auto.tfvars.json`

JSON form of `subscription_slots` plus the VPN access group object ID and the deployment app's client ID. Consumed automatically by `tofu plan` because of the `.auto.tfvars.json` suffix.

```json
{
  "subscription_slots": {
    "hub":    { "subscription_id": "11111111-1111-1111-1111-111111111111" },
    "demo_a": { "subscription_id": "22222222-2222-2222-2222-222222222222" }
  },
  "vpn_access_group_object_id": "33333333-3333-3333-3333-333333333333",
  "deployment_app_client_id": "44444444-4444-4444-4444-444444444444",
  "tenant_id": "00000000-0000-0000-0000-000000000000"
}
```

### `bootstrap-report.md`

Human-readable summary the operator reads before committing the pipeline scoping. Lists:

- The display names + object IDs created.
- Every role assignment created (scope, role, principal).
- Every federated credential created (subject, issuer, audience).
- The state account RBAC.
- Any pre-existing objects that were left alone.

### GitHub Actions secrets / variables to set (printed at end of script)

The script does NOT touch GitHub. It prints exactly what the operator needs to configure in the repo settings:

- Repository **Variables** (not secrets): `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID` (= `HubSubscriptionId`), `TF_STATE_SUBSCRIPTION_ID`, `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`.
- Repository **Secrets**: none. (Principle III.)

## Re-run semantics

- Running with the same inputs is a no-op.
- Running after adding a new subscription to the tenant creates the two new role assignments for that subscription and updates `discovered.auto.tfvars.json` with the new slot entry. The operator still needs to add a matching `provider "azurerm"` alias to `infra/providers.tf` (one-time HCL edit) before plan can use the new slot.
- Running after deleting a subscription leaves the historical role assignments orphaned (Azure auto-purges them within ~30 days); the script logs but does not error.

## Failure modes

| Symptom | Likely cause | Remediation |
|---|---|---|
| `Insufficient privileges to complete the operation` on `az ad app create` | Operator lacks `Application Administrator` (or higher) in Entra. | Operator must obtain the role and re-run. |
| `Forbidden: principal does not have access` on `az role assignment create` | Operator lacks `User Access Administrator` on the target subscription. | Operator escalates per their org's process, then re-runs. |
| `Federated credential already exists` with different subject | Stale credential from a prior repo / branch scoping. | Inspect via `az ad app federated-credential list` and decide whether to delete or keep. |
| Plan fails with "unknown subscription slot" after bootstrap added a new sub | `infra/providers.tf` not yet updated with the new alias block. | Add the alias; commit; re-run plan. |
