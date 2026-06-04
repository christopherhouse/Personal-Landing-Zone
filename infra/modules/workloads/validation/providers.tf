# Provider requirements for the validation workload module.
#
# Inherits the spoke-context azurerm provider from the caller; the storage
# AVM uses azapi internally so that must be declared too. The tls provider
# generates a throwaway SSH key whose private half is intentionally not
# persisted to state outputs.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
