terraform {
  # Partial-configuration backend. Coordinates (subscription_id,
  # resource_group_name, storage_account_name, container_name, key) are
  # injected via -backend-config=... on `tofu init` in the GitHub Actions
  # workflows (.github/workflows/plan.yml and apply.yml), sourced from
  # repository Variables emitted by bootstrap.ps1.
  #
  # Auth: OIDC workload identity federation + AAD data-plane (no keys, no SAS).
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}
