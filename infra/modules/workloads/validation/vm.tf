locals {
  vm_name  = "vm-${var.naming_prefix}-validation"
  nic_name = "nic-${var.naming_prefix}-validation"
}

# Throwaway SSH key required by azurerm_linux_virtual_machine (and the VM AVM)
# — the public half is the only piece that ever leaves Terraform-the-process.
# Real interactive access is via `az ssh vm` with the AADSSHLoginForLinux
# extension below (research.md R-008).
resource "tls_private_key" "throwaway" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

module "vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.20"

  name                = local.vm_name
  location            = var.region
  resource_group_name = var.target_resource_group_name
  os_type             = "Linux"
  sku_size            = "Standard_B1s"
  zone                = null
  enable_telemetry    = false
  tags                = var.tags

  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  account_credentials = {
    admin_credentials = {
      username                           = "azureuser"
      ssh_keys                           = [tls_private_key.throwaway.public_key_openssh]
      generate_admin_password_or_ssh_key = false
    }
    password_authentication_disabled = true
  }

  managed_identities = {
    system_assigned = true
  }

  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interfaces = {
    primary = {
      name = local.nic_name
      ip_configurations = {
        primary = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = var.target_subnet_id
          private_ip_address_allocation = "Dynamic"
          is_primary_ipconfiguration    = true
          create_public_ip_address      = false
        }
      }
    }
  }

  extensions = {
    aad_ssh = {
      name                       = "AADSSHLoginForLinux"
      publisher                  = "Microsoft.Azure.ActiveDirectory"
      type                       = "AADSSHLoginForLinux"
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
    }
  }
}
