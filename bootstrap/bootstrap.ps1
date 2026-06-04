<#
.SYNOPSIS
    Idempotent bootstrap for the Hub-and-Spoke Networking Foundation.

.DESCRIPTION
    Runs once per Entra tenant (and incrementally when new subscriptions are
    added). All Azure-side actions are idempotent: re-running with the same
    inputs is a no-op. No client secrets, SAS tokens, or storage keys are ever
    created — auth flows are Entra OIDC end-to-end.

    See specs/001-hub-spoke-foundation/contracts/bootstrap-inputs.md for the
    authoritative contract.

    Authoring is layered so each task in tasks.md (T012-T017) corresponds to a
    labelled region below.

.NOTES
    Requires: az CLI >= 2.62; an interactive `az login --tenant <TenantId>`
    completed before running. The operator's signed-in identity is the only
    Microsoft Graph caller; the deployment SP receives ZERO Graph permissions.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $TenantId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $HubSubscriptionId,

    [Parameter(Mandatory)]
    [ValidatePattern('^rg-[a-z0-9-]+$')]
    [string] $HubResourceGroupName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $StateSubscriptionId,

    [Parameter(Mandatory)]
    [string] $StateResourceGroupName,

    [Parameter(Mandatory)]
    [string] $StateStorageAccountName,

    [Parameter(Mandatory)]
    [string] $StateContainerName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string] $GithubRepository,

    [Parameter(Mandatory)]
    [string[]] $GithubBranchOrEnvironment,

    [Parameter()]
    [string] $DeploymentAppDisplayName = 'app-plz-deploy',

    [Parameter()]
    [string] $VpnAccessGroupDisplayName = 'sg-plz-vpn-users',

    [Parameter()]
    [string] $Region = 'eastus2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =====================================================================
# Helpers
# =====================================================================

function Write-Step {
    param([string] $Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string] $Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Write-Created {
    param([string] $Message)
    Write-Host "    [created] $Message" -ForegroundColor Green
}

function Write-Existing {
    param([string] $Message)
    Write-Host "    [exists]  $Message" -ForegroundColor DarkGray
}

function Invoke-Az {
    # Wrapper that runs `az` with --only-show-errors and parses JSON output.
    # Returns $null if the command produced no output.
    param([Parameter(Mandatory)][string[]] $AzArgs)
    $output = & az @AzArgs --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($AzArgs -join ' ') failed: $output"
    }
    if (-not $output) { return $null }
    try { return ($output | Out-String | ConvertFrom-Json) }
    catch { return $output }
}

function ConvertTo-SlotName {
    # Lowercase + replace non-[a-z0-9] runs with "_"; trim leading underscores.
    param([string] $Raw)
    $slug = ($Raw.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrEmpty($slug)) { $slug = 'sub' }
    # Slot names must start with [a-z]; prepend "s" if first char is a digit.
    if ($slug -match '^[0-9]') { $slug = "s_$slug" }
    return $slug
}

# Per-run mutation log; consumed by bootstrap-report.md writer (T017).
$script:CreatedObjects     = [System.Collections.Generic.List[object]]::new()
$script:ExistingObjects    = [System.Collections.Generic.List[object]]::new()
$script:RoleAssignments    = [System.Collections.Generic.List[object]]::new()
$script:FederatedCreds     = [System.Collections.Generic.List[object]]::new()

function Add-CreatedObject {
    param([string] $Kind, [string] $Name, [string] $Id = '')
    $script:CreatedObjects.Add([pscustomobject]@{ Kind = $Kind; Name = $Name; Id = $Id })
    Write-Created "$Kind $Name $(if ($Id) { "($Id)" } else { '' })"
}
function Add-ExistingObject {
    param([string] $Kind, [string] $Name, [string] $Id = '')
    $script:ExistingObjects.Add([pscustomobject]@{ Kind = $Kind; Name = $Name; Id = $Id })
    Write-Existing "$Kind $Name $(if ($Id) { "($Id)" } else { '' })"
}

# =====================================================================
# T012 — Pre-flight
# =====================================================================

Write-Step 'Pre-flight checks'

# 1. az logged in?
$account = $null
try { $account = Invoke-Az @('account', 'show') }
catch { throw "az is not logged in. Run 'az login --tenant $TenantId' and retry." }

# 2. Tenant match?
if ($account.tenantId -ne $TenantId) {
    throw "az is logged in to tenant $($account.tenantId), but -TenantId is $TenantId. Run 'az login --tenant $TenantId' and retry."
}
Write-Info "Signed in as $($account.user.name) in tenant $TenantId."

# 3. State storage account reachable from current sub context?
Invoke-Az @('account', 'set', '--subscription', $StateSubscriptionId) | Out-Null
try {
    $stateAccount = Invoke-Az @(
        'storage', 'account', 'show',
        '--name', $StateStorageAccountName,
        '--resource-group', $StateResourceGroupName
    )
}
catch {
    throw "State storage account '$StateStorageAccountName' in RG '$StateResourceGroupName' (sub $StateSubscriptionId) could not be read. Verify the coordinates and that your account has at least Reader on it. Underlying error: $_"
}
Write-Info "State account $($stateAccount.name) reachable (kind=$($stateAccount.kind))."
$stateAccountResourceId = $stateAccount.id

# 4. Verify the operator can hit Microsoft Graph (Entra-side create privileges).
#    A lightweight read with --filter on signed-in user is sufficient.
try {
    Invoke-Az @('ad', 'signed-in-user', 'show') | Out-Null
}
catch {
    throw "Microsoft Graph is unreachable for the signed-in operator. The agent cannot create Entra objects. Underlying error: $_"
}

# Restore default sub context to the hub for the remainder of the run.
Invoke-Az @('account', 'set', '--subscription', $HubSubscriptionId) | Out-Null

# =====================================================================
# T013 — Subscription enumeration & slot map derivation
# =====================================================================

Write-Step 'Enumerating subscriptions in tenant'

$tenantSubs = Invoke-Az @('account', 'list', '--query', "[?tenantId=='$TenantId']")
if (-not $tenantSubs -or $tenantSubs.Count -eq 0) {
    throw "No subscriptions found for tenant $TenantId. Run 'az account list' to inspect."
}

# Build $slotMap: ordered hashtable of slot_name -> subscription metadata.
# The hub sub is forced to slot name 'hub' regardless of its display name.
$slotMap = [ordered]@{}

$hubSub = $tenantSubs | Where-Object { $_.id -eq $HubSubscriptionId } | Select-Object -First 1
if (-not $hubSub) {
    throw "Hub subscription $HubSubscriptionId not found in tenant $TenantId. Verify -HubSubscriptionId or your tenant membership."
}
$slotMap['hub'] = [pscustomobject]@{
    subscription_id = $hubSub.id
    display_name    = $hubSub.name
}
Write-Info ("slot 'hub' -> {0} ({1})" -f $hubSub.name, $hubSub.id)

foreach ($sub in $tenantSubs | Where-Object { $_.id -ne $HubSubscriptionId } | Sort-Object name) {
    $slotName = ConvertTo-SlotName -Raw $sub.name
    # De-collide if two subs slugify to the same name.
    $candidate = $slotName
    $suffix = 2
    while ($slotMap.Contains($candidate)) {
        $candidate = "${slotName}_$suffix"
        $suffix++
    }
    $slotMap[$candidate] = [pscustomobject]@{
        subscription_id = $sub.id
        display_name    = $sub.name
    }
    Write-Info ("slot '$candidate' -> {0} ({1})" -f $sub.name, $sub.id)
}

# =====================================================================
# T014 — Deployment Entra app + SP + federated credentials (no secrets)
# =====================================================================

Write-Step "Ensuring deployment Entra application '$DeploymentAppDisplayName'"

$existingApp = Invoke-Az @('ad', 'app', 'list', '--display-name', $DeploymentAppDisplayName)
if ($existingApp -and ($existingApp | Measure-Object).Count -gt 0) {
    $app = $existingApp | Select-Object -First 1
    Add-ExistingObject 'Entra application' $DeploymentAppDisplayName $app.appId
}
else {
    $app = Invoke-Az @('ad', 'app', 'create', '--display-name', $DeploymentAppDisplayName, '--sign-in-audience', 'AzureADMyOrg')
    Add-CreatedObject 'Entra application' $DeploymentAppDisplayName $app.appId
}
$appId       = $app.appId
$appObjectId = $app.id

Write-Step "Ensuring service principal for app $appId"
$existingSp = Invoke-Az @('ad', 'sp', 'list', '--filter', "appId eq '$appId'")
if ($existingSp -and ($existingSp | Measure-Object).Count -gt 0) {
    $sp = $existingSp | Select-Object -First 1
    Add-ExistingObject 'Service principal' "for $DeploymentAppDisplayName" $sp.id
}
else {
    $sp = Invoke-Az @('ad', 'sp', 'create', '--id', $appId)
    Add-CreatedObject 'Service principal' "for $DeploymentAppDisplayName" $sp.id
}
$spObjectId = $sp.id

# Federated credentials — one per supplied -GithubBranchOrEnvironment value.
Write-Step "Ensuring federated credentials for repository $GithubRepository"
$existingCreds = Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appObjectId)
$existingCredNames = @()
if ($existingCreds) { $existingCredNames = $existingCreds | ForEach-Object { $_.name } }

foreach ($spec in $GithubBranchOrEnvironment) {
    switch -Regex ($spec) {
        '^branch:(.+)$' {
            $branchName = $Matches[1]
            $credName   = "github-$($GithubRepository -replace '/', '-')-branch-$($branchName -replace '[^A-Za-z0-9-]', '-')"
            $subject    = "repo:$GithubRepository`:ref:refs/heads/$branchName"
            break
        }
        '^environment:(.+)$' {
            $envName  = $Matches[1]
            $credName = "github-$($GithubRepository -replace '/', '-')-env-$($envName -replace '[^A-Za-z0-9-]', '-')"
            $subject  = "repo:$GithubRepository`:environment:$envName"
            break
        }
        '^pull_request$' {
            $credName = "github-$($GithubRepository -replace '/', '-')-pull-request"
            $subject  = "repo:$GithubRepository`:pull_request"
            break
        }
        default {
            throw "Unrecognized -GithubBranchOrEnvironment value: '$spec'. Expected 'branch:<name>', 'environment:<name>', or 'pull_request'."
        }
    }

    $credEntry = [pscustomobject]@{
        Name    = $credName
        Subject = $subject
        Issuer  = 'https://token.actions.githubusercontent.com'
        Audience = 'api://AzureADTokenExchange'
    }

    if ($existingCredNames -contains $credName) {
        Add-ExistingObject 'Federated credential' $credName ''
        $script:FederatedCreds.Add($credEntry)
        continue
    }

    $params = @{
        name      = $credName
        issuer    = 'https://token.actions.githubusercontent.com'
        subject   = $subject
        audiences = @('api://AzureADTokenExchange')
    }
    $paramsJsonPath = New-TemporaryFile
    $params | ConvertTo-Json -Depth 5 | Set-Content -Path $paramsJsonPath -Encoding utf8
    try {
        Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $appObjectId, '--parameters', "@$paramsJsonPath") | Out-Null
        Add-CreatedObject 'Federated credential' $credName ''
        $script:FederatedCreds.Add($credEntry)
    }
    finally {
        Remove-Item -Path $paramsJsonPath -Force -ErrorAction SilentlyContinue
    }
}

# =====================================================================
# T015 — VPN access Entra group
# =====================================================================

Write-Step "Ensuring VPN access Entra group '$VpnAccessGroupDisplayName'"
$existingGroup = Invoke-Az @('ad', 'group', 'list', '--display-name', $VpnAccessGroupDisplayName)
if ($existingGroup -and ($existingGroup | Measure-Object).Count -gt 0) {
    $vpnGroup = $existingGroup | Select-Object -First 1
    Add-ExistingObject 'Entra security group' $VpnAccessGroupDisplayName $vpnGroup.id
}
else {
    $mailNickname = ($VpnAccessGroupDisplayName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
    if ([string]::IsNullOrEmpty($mailNickname)) { $mailNickname = 'vpnusers' }
    $vpnGroup = Invoke-Az @(
        'ad', 'group', 'create',
        '--display-name', $VpnAccessGroupDisplayName,
        '--mail-nickname', $mailNickname
    )
    Add-CreatedObject 'Entra security group' $VpnAccessGroupDisplayName $vpnGroup.id
}
$vpnGroupObjectId = $vpnGroup.id

# =====================================================================
# T016 — Role assignments
# =====================================================================

function Set-RoleAssignmentIdempotent {
    param(
        [string] $RoleName,
        [string] $Scope,
        [string] $PrincipalId
    )
    # Existence check by (role, principal, scope). Note: `az role assignment
    # list` does not accept `--assignee-principal-type` (only `create` does);
    # `--assignee-object-id` alone is unambiguous.
    $existing = Invoke-Az @(
        'role', 'assignment', 'list',
        '--assignee', $PrincipalId,
        '--role', $RoleName,
        '--scope', $Scope
    )
    if ($existing -and ($existing | Measure-Object).Count -gt 0) {
        Add-ExistingObject 'Role assignment' "$RoleName @ $Scope -> $PrincipalId"
        $script:RoleAssignments.Add([pscustomobject]@{ Role = $RoleName; Scope = $Scope; PrincipalId = $PrincipalId; State = 'existed' })
        return
    }
    Invoke-Az @(
        'role', 'assignment', 'create',
        '--assignee-object-id', $PrincipalId,
        '--assignee-principal-type', 'ServicePrincipal',
        '--role', $RoleName,
        '--scope', $Scope
    ) | Out-Null
    Add-CreatedObject 'Role assignment' "$RoleName @ $Scope -> $PrincipalId"
    $script:RoleAssignments.Add([pscustomobject]@{ Role = $RoleName; Scope = $Scope; PrincipalId = $PrincipalId; State = 'created' })
}

Write-Step 'Assigning Contributor + User Access Administrator per enumerated subscription'
foreach ($slot in $slotMap.Keys) {
    $subId  = $slotMap[$slot].subscription_id
    $scope  = "/subscriptions/$subId"
    Set-RoleAssignmentIdempotent -RoleName 'Contributor'                  -Scope $scope -PrincipalId $spObjectId
    Set-RoleAssignmentIdempotent -RoleName 'User Access Administrator'    -Scope $scope -PrincipalId $spObjectId
}

Write-Step 'Assigning Storage Blob Data Contributor on state storage account'
Set-RoleAssignmentIdempotent -RoleName 'Storage Blob Data Contributor' -Scope $stateAccountResourceId -PrincipalId $spObjectId

# =====================================================================
# T017 — Output writers
# =====================================================================

Write-Step 'Writing bootstrap outputs'

$outputsDir = Join-Path $PSScriptRoot 'outputs'
if (-not (Test-Path -Path $outputsDir)) {
    New-Item -ItemType Directory -Path $outputsDir | Out-Null
}

# discovered.auto.tfvars.json — consumed at `tofu plan` time.
$discovered = [ordered]@{
    subscription_slots = [ordered]@{}
    vpn_access_group_object_id = $vpnGroupObjectId
    deployment_app_client_id   = $appId
    tenant_id                  = $TenantId
}
foreach ($slot in $slotMap.Keys) {
    $discovered.subscription_slots[$slot] = [ordered]@{
        subscription_id = $slotMap[$slot].subscription_id
    }
}
$discoveredPath = Join-Path $outputsDir 'discovered.auto.tfvars.json'
$discovered | ConvertTo-Json -Depth 6 | Set-Content -Path $discoveredPath -Encoding utf8
Write-Info "Wrote $discoveredPath"

# bootstrap-report.md — human-readable summary.
$reportPath = Join-Path $outputsDir 'bootstrap-report.md'
$report = [System.Text.StringBuilder]::new()
[void]$report.AppendLine("# Bootstrap Report")
[void]$report.AppendLine()
[void]$report.AppendLine("**Tenant**: ``$TenantId``  ")
[void]$report.AppendLine("**Hub subscription**: ``$HubSubscriptionId``  ")
[void]$report.AppendLine("**Generated**: $(Get-Date -Format o)  ")
[void]$report.AppendLine("**Operator**: $($account.user.name)")
[void]$report.AppendLine()
[void]$report.AppendLine("## Enumerated subscription slots")
[void]$report.AppendLine()
[void]$report.AppendLine('| Slot | Subscription ID | Display name |')
[void]$report.AppendLine('|---|---|---|')
foreach ($slot in $slotMap.Keys) {
    [void]$report.AppendLine("| ``$slot`` | ``$($slotMap[$slot].subscription_id)`` | $($slotMap[$slot].display_name) |")
}
[void]$report.AppendLine()
[void]$report.AppendLine("## Deployment service principal")
[void]$report.AppendLine()
[void]$report.AppendLine("- **App display name**: ``$DeploymentAppDisplayName``")
[void]$report.AppendLine("- **App (client) ID**: ``$appId``")
[void]$report.AppendLine("- **Service principal object ID**: ``$spObjectId``")
[void]$report.AppendLine("- **Client secret**: none — federated credentials only.")
[void]$report.AppendLine()
[void]$report.AppendLine("## Federated credentials")
[void]$report.AppendLine()
[void]$report.AppendLine('| Name | Subject | Issuer | Audience |')
[void]$report.AppendLine('|---|---|---|---|')
foreach ($cred in $script:FederatedCreds) {
    [void]$report.AppendLine("| ``$($cred.Name)`` | ``$($cred.Subject)`` | ``$($cred.Issuer)`` | ``$($cred.Audience)`` |")
}
[void]$report.AppendLine()
[void]$report.AppendLine("## VPN access group")
[void]$report.AppendLine()
[void]$report.AppendLine("- **Display name**: ``$VpnAccessGroupDisplayName``")
[void]$report.AppendLine("- **Object ID**: ``$vpnGroupObjectId``")
[void]$report.AppendLine("- **Member management**: add operator(s) to this group via the Entra portal or ``az ad group member add`` to grant VPN access.")
[void]$report.AppendLine()
[void]$report.AppendLine("## Role assignments")
[void]$report.AppendLine()
[void]$report.AppendLine('| Role | Scope | Principal | State |')
[void]$report.AppendLine('|---|---|---|---|')
foreach ($ra in $script:RoleAssignments) {
    [void]$report.AppendLine("| $($ra.Role) | ``$($ra.Scope)`` | ``$($ra.PrincipalId)`` | $($ra.State) |")
}
[void]$report.AppendLine()
[void]$report.AppendLine("## State storage account")
[void]$report.AppendLine()
[void]$report.AppendLine("- **Subscription**: ``$StateSubscriptionId``")
[void]$report.AppendLine("- **Resource group**: ``$StateResourceGroupName``")
[void]$report.AppendLine("- **Account**: ``$StateStorageAccountName``")
[void]$report.AppendLine("- **Container**: ``$StateContainerName``")
[void]$report.AppendLine("- **Resource ID**: ``$stateAccountResourceId``")
[void]$report.AppendLine()
[void]$report.AppendLine("## Pre-existing objects (left alone)")
[void]$report.AppendLine()
if ($script:ExistingObjects.Count -eq 0) {
    [void]$report.AppendLine("_None — every object listed above was created by this run._")
}
else {
    [void]$report.AppendLine('| Kind | Name | ID |')
    [void]$report.AppendLine('|---|---|---|')
    foreach ($obj in $script:ExistingObjects) {
        [void]$report.AppendLine("| $($obj.Kind) | $($obj.Name) | ``$($obj.Id)`` |")
    }
}
[void]$report.AppendLine()
[void]$report.AppendLine("## GitHub Actions repository Variables to set")
[void]$report.AppendLine()
[void]$report.AppendLine("Set these as **repository Variables** (not Secrets) under Settings -> Secrets and variables -> Actions -> Variables tab:")
[void]$report.AppendLine()
[void]$report.AppendLine('| Variable | Value |')
[void]$report.AppendLine('|---|---|')
[void]$report.AppendLine("| ``ARM_TENANT_ID`` | ``$TenantId`` |")
[void]$report.AppendLine("| ``ARM_CLIENT_ID`` | ``$appId`` |")
[void]$report.AppendLine("| ``ARM_SUBSCRIPTION_ID`` | ``$HubSubscriptionId`` |")
[void]$report.AppendLine("| ``TF_STATE_SUBSCRIPTION_ID`` | ``$StateSubscriptionId`` |")
[void]$report.AppendLine("| ``TF_STATE_RESOURCE_GROUP`` | ``$StateResourceGroupName`` |")
[void]$report.AppendLine("| ``TF_STATE_STORAGE_ACCOUNT`` | ``$StateStorageAccountName`` |")
[void]$report.AppendLine("| ``TF_STATE_CONTAINER`` | ``$StateContainerName`` |")
[void]$report.AppendLine()
[void]$report.AppendLine("No repository Secrets are required (Constitution Principle III).")

Set-Content -Path $reportPath -Value $report.ToString() -Encoding utf8
Write-Info "Wrote $reportPath"

Write-Step 'Bootstrap complete'
Write-Host ''
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review $reportPath" -ForegroundColor Yellow
Write-Host "  2. Set the GitHub Actions repository Variables listed in the report." -ForegroundColor Yellow
Write-Host "  3. Add yourself (and other VPN users) to the '$VpnAccessGroupDisplayName' Entra group." -ForegroundColor Yellow
Write-Host "  4. Commit $discoveredPath to your feature branch and open the initial deployment PR." -ForegroundColor Yellow
Write-Host ''
