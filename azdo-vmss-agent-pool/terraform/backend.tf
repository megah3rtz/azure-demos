terraform {
  backend "azurerm" {
    subscription_id      = "f7e9b3e5-ddde-49b3-a174-5d734241380e"
    resource_group_name  = "terraform-rg"
    storage_account_name = "terraformstate99"
    container_name       = "terraformstate"
    key                  = "azdo-vmss-agent-pool.tfstate"
  }
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}