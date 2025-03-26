provider "azurerm" {
  features {}
}

locals {
  virtual_networks = merge(var.global_settings.hub_virtual_networks, var.global_settings.spoke_virtual_networks)
}

data "azurerm_subscription" "current" {}
module "naming" {
  # checkov:skip=CKV_TF_1:Not using commit hashes to pin dependencies
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
  prefix  = ["${var.location-map[var.location]}"]
}

resource "azurerm_resource_group" "resourcegroup" {
  name     = module.naming.resource_group.name
  location = var.location
}

resource "azurerm_virtual_network" "example" {
  for_each            = local.virtual_networks
  name                = "${module.naming.virtual_network.name}-${each.key}"
  location            = azurerm_resource_group.resourcegroup.location
  resource_group_name = azurerm_resource_group.resourcegroup.name
  address_space       = try(["${cidrsubnet(each.value.address_space, 8, each.value.netnum)}"], ["${cidrsubnet(var.global_settings.address_space, 8, each.value.netnum)}"])
}

resource "azurerm_subnet" "example" {
  for_each             = local.virtual_networks
  name                 = "${module.naming.subnet.name}-${each.key}"
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  virtual_network_name = azurerm_virtual_network.example[each.key].name
  address_prefixes     = try(["${cidrsubnet(cidrsubnet(each.value.address_space, 8, each.value.netnum), 2, 0)}"], ["${cidrsubnet(cidrsubnet(var.global_settings.address_space, 8, each.value.netnum), 2, 0)}"])
}

resource "azurerm_virtual_network_peering" "peer1" {
  for_each                     = var.global_settings.spoke_virtual_networks
  name                         = "${module.naming.virtual_network_peering.name}-${each.key}"
  resource_group_name          = azurerm_resource_group.resourcegroup.name
  virtual_network_name         = azurerm_virtual_network.example["hub"].name
  remote_virtual_network_id    = azurerm_virtual_network.example[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "peer2" {
  for_each                     = var.global_settings.spoke_virtual_networks
  name                         = "${module.naming.virtual_network_peering.name}-${each.key}"
  resource_group_name          = azurerm_resource_group.resourcegroup.name
  virtual_network_name         = azurerm_virtual_network.example[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.example["hub"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_linux_virtual_machine_scale_set" "deployment" {
  name                = module.naming.virtual_machine_scale_set.name
  resource_group_name = azurerm_resource_group.resourcegroup.name
  location            = azurerm_resource_group.resourcegroup.location
  sku                 = "Standard_A2_v2"
  instances           = 0 # number of instances

  overprovision          = false
  single_placement_group = false

  priority                   = "Spot"
  eviction_policy            = "Deallocate"
  max_bid_price              = "0.011"
  encryption_at_host_enabled = true

  admin_username = "adminuser"
  admin_ssh_key {
    username   = "adminuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCpZBNIh82yTjyCJzU2hwAS/QDrES5qHRJN6WYZoA0BM6VWpHls8qse6usQA5XCPREav6KR+vO5UWdynqxBHqJ17vaQLcQ0HshXvPUA7TL0W9lw//wYE2zvbawuobXSf12P6ryq8LbURIo68I5P0/82eDk6zxi1OljcJuhEVTgj/CfywQdR7QxXAGwdLFwiCTN59gROcVFSmhTvXHd1dEB4Nrte3AmHa9HQgGKKlkP3Swyqpu6hl3pqa6lnwX07Z88M4mewE1nJadHycrSBAH2Gfh7Lm1P+aDfw799rdMcWcNY2ll/kMNrMMGGQ3XJf/RpcL2qYcjAQNzpn4yjEdqX/ThBHUBHcVcNr3PTHq9ItxIdEBa9NZT1h4NwsAkayZ9RKlVe/ncdP8G8RK4BfGt1rWF4Mk6+7sh2fpc8HuvwXCxpqiebaBhghv28AxKQwjizYpg1Uc8OjN4Zj5/no0+jF/ch3ULXnf6JjEHrS/xO4B3wuKOoRVraIrkbVo6AV6JM="
  }
  disable_password_authentication = true

  custom_data = base64encode(data.local_file.cloudinit.content)

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadOnly"

    # diff_disk_settings {
    #   option = "Local"
    # }
  }

  network_interface {
    name    = module.naming.network_interface.name
    primary = true

    ip_configuration {
      name      = "vmss-ip-config"
      primary   = true
      subnet_id = azurerm_subnet.example["spoke1"].id
    }
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  tags = {
    environment              = "prod"
    __AzureDevOpsElasticPool = "vmss-pool"
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.deployment.id]
  }
}

# Data template Bash bootstrapping file
data "local_file" "cloudinit" {
  filename = "${path.module}/cloudinit.conf"
}

resource "azurerm_user_assigned_identity" "deployment" {
  resource_group_name = azurerm_resource_group.resourcegroup.name
  location            = azurerm_resource_group.resourcegroup.location
  name                = module.naming.user_assigned_identity.name
}

resource "azurerm_role_assignment" "deployment" {
  scope                = azurerm_resource_group.resourcegroup.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.deployment.principal_id
}