# Grant the VPN access Entra group both interactive-login rights on the VM
# (via Entra-issued SSH cert) and read access to blob data on the storage
# account, so a VPN-connected member can prove SC-001 end-to-end with
# `az ssh vm` + `az storage blob list --auth-mode login`.

resource "azurerm_role_assignment" "vm_user_login" {
  scope                = module.vm.resource_id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.vpn_access_group_object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "blob_data_reader" {
  scope                = module.storage.resource_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.vpn_access_group_object_id
  principal_type       = "Group"
}
