# Bootstrap Report

**Tenant**: `76de2d2d-77f8-438d-9a87-01806f2345da`  
**Hub subscription**: `f8b910d5-ed06-4f0f-bf36-c8167bba60eb`  
**Generated**: 2026-06-04T18:38:58.3696268-05:00  
**Operator**: chhouse@microsoft.com

## Enumerated subscription slots

| Slot | Subscription ID | Display name |
|---|---|---|
| `hub` | `f8b910d5-ed06-4f0f-bf36-c8167bba60eb` | ME-MngEnvMCAP064264-chhouse-1 |
| `me_mngenvmcap064264_chhouse_2` | `8bd05b2f-62c5-4def-9869-f0617ebb3970` | ME-MngEnvMCAP064264-chhouse-2 |
| `me_mngenvmcap064264_chhouse_3` | `c5d4a6e8-69bf-4148-be25-cb362f83c370` | ME-MngEnvMCAP064264-chhouse-3 |
| `me_mngenvmcap064264_chhouse_9` | `47046546-29e0-4be5-bdda-78a53f62b992` | ME-MngEnvMCAP064264-chhouse-9 |

## Deployment service principal

- **App display name**: `app-plz-deploy`
- **App (client) ID**: `8098472d-89ea-40dd-912b-09d3ba090a82`
- **Service principal object ID**: `f3d812ef-36d1-45a4-a730-c556d2fbdbf5`
- **Client secret**: none — federated credentials only.

## Federated credentials

| Name | Subject | Issuer | Audience |
|---|---|---|---|
| `github-christopherhouse-Personal-Landing-Zone-branch-main` | `repo:christopherhouse/Personal-Landing-Zone:ref:refs/heads/main` | `https://token.actions.githubusercontent.com` | `api://AzureADTokenExchange` |
| `github-christopherhouse-Personal-Landing-Zone-pull-request` | `repo:christopherhouse/Personal-Landing-Zone:pull_request` | `https://token.actions.githubusercontent.com` | `api://AzureADTokenExchange` |

## VPN access group

- **Display name**: `sg-plz-vpn-users`
- **Object ID**: `62e8779c-c34e-47be-a91e-ee64b8c7edf3`
- **Member management**: add operator(s) to this group via the Entra portal or `az ad group member add` to grant VPN access.

## Role assignments

| Role | Scope | Principal | State |
|---|---|---|---|
| Contributor | `/subscriptions/f8b910d5-ed06-4f0f-bf36-c8167bba60eb` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| User Access Administrator | `/subscriptions/f8b910d5-ed06-4f0f-bf36-c8167bba60eb` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| Contributor | `/subscriptions/8bd05b2f-62c5-4def-9869-f0617ebb3970` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| User Access Administrator | `/subscriptions/8bd05b2f-62c5-4def-9869-f0617ebb3970` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| Contributor | `/subscriptions/c5d4a6e8-69bf-4148-be25-cb362f83c370` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| User Access Administrator | `/subscriptions/c5d4a6e8-69bf-4148-be25-cb362f83c370` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| Contributor | `/subscriptions/47046546-29e0-4be5-bdda-78a53f62b992` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| User Access Administrator | `/subscriptions/47046546-29e0-4be5-bdda-78a53f62b992` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |
| Storage Blob Data Contributor | `/subscriptions/8bd05b2f-62c5-4def-9869-f0617ebb3970/resourceGroups/RG-TF/providers/Microsoft.Storage/storageAccounts/cmhtfstatesa` | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` | created |

## State storage account

- **Subscription**: `8bd05b2f-62c5-4def-9869-f0617ebb3970`
- **Resource group**: `RG-TF`
- **Account**: `cmhtfstatesa`
- **Container**: `tfstate`
- **Resource ID**: `/subscriptions/8bd05b2f-62c5-4def-9869-f0617ebb3970/resourceGroups/RG-TF/providers/Microsoft.Storage/storageAccounts/cmhtfstatesa`

## Pre-existing objects (left alone)

| Kind | Name | ID |
|---|---|---|
| Entra application | app-plz-deploy | `8098472d-89ea-40dd-912b-09d3ba090a82` |
| Service principal | for app-plz-deploy | `f3d812ef-36d1-45a4-a730-c556d2fbdbf5` |
| Federated credential | github-christopherhouse-Personal-Landing-Zone-branch-main | `` |
| Federated credential | github-christopherhouse-Personal-Landing-Zone-pull-request | `` |
| Entra security group | sg-plz-vpn-users | `62e8779c-c34e-47be-a91e-ee64b8c7edf3` |

## GitHub Actions repository Variables to set

Set these as **repository Variables** (not Secrets) under Settings -> Secrets and variables -> Actions -> Variables tab:

| Variable | Value |
|---|---|
| `ARM_TENANT_ID` | `76de2d2d-77f8-438d-9a87-01806f2345da` |
| `ARM_CLIENT_ID` | `8098472d-89ea-40dd-912b-09d3ba090a82` |
| `ARM_SUBSCRIPTION_ID` | `f8b910d5-ed06-4f0f-bf36-c8167bba60eb` |
| `TF_STATE_SUBSCRIPTION_ID` | `8bd05b2f-62c5-4def-9869-f0617ebb3970` |
| `TF_STATE_RESOURCE_GROUP` | `RG-TF` |
| `TF_STATE_STORAGE_ACCOUNT` | `cmhtfstatesa` |
| `TF_STATE_CONTAINER` | `tfstate` |

No repository Secrets are required (Constitution Principle III).

