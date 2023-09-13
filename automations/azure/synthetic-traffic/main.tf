terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # this makes it easier to clean up
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "random" {}

data "azurerm_client_config" "current" {}

data "azuread_user" "current_user" {
  object_id = data.azurerm_client_config.current.object_id
}

data "azurerm_resource_group" "this" {
  name = var.resource_group
}

data "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "random_pet" "deployment_id" {
  keepers = {
    created_by = local.created_by
    rg_cidr    = var.resource_group
  }
}

resource "azurerm_subnet" "subnets" {
  for_each = local.subnets
  name     = each.value.name
  # name                 = each.key == "AzureBastionSubnet" ? "AzureBastionSubnet" : "${local.label}-${each.key}-${local.deployment_id}"
  resource_group_name  = data.azurerm_virtual_network.this.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}

resource "azurerm_route_table" "rt" {
  for_each            = local.routes
  name                = "${local.label}-${each.key}-${local.deployment_id}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
}

resource "azurerm_route" "routes" {
  for_each               = local.routes
  name                   = "${local.label}-${each.key}-${local.deployment_id}"
  resource_group_name    = data.azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.rt[each.key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_type == "VirtualAppliance" ? each.value.next_hop_in_ip_address : null
  depends_on = [
    azurerm_route_table.rt
  ]
}

resource "azurerm_subnet_route_table_association" "subnets_rt_association" {
  for_each       = local.routes
  subnet_id      = azurerm_subnet.subnets[each.value.subnet_association].id
  route_table_id = azurerm_route_table.rt[each.key].id
  depends_on = [
    azurerm_subnet.subnets,
    azurerm_route_table.rt
  ]
}

resource "azurerm_public_ip" "vms_public_ips" {
  for_each            = { for k, v in local.vms : k => v if v.public_ip_address }
  name                = "${local.label}-${each.key}-vm-public-ip-${local.deployment_id}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Dynamic"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-vm-public-ip-${local.deployment_id}" })
}

resource "azurerm_network_security_group" "nsg" {
  for_each            = local.nsg
  name                = "${local.label}-${each.key}-nsg-${local.deployment_id}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-nsg-${local.deployment_id}" })
}

locals {
  nsg_list = flatten([
    for nsgk, nsgv in local.nsg : [
      for appk, appv in nsgv : {
        nsg_name                   = nsgk
        sg_name                    = appk
        priority                   = appv.priority
        direction                  = appv.direction
        access                     = appv.access
        protocol                   = appv.protocol
        source_port_range          = appv.source_port_range
        destination_port_range     = appv.destination_port_range
        source_address_prefix      = appv.source_address_prefix
        destination_address_prefix = appv.destination_address_prefix
      }
    ]
  ])
}

resource "azurerm_network_security_rule" "nsg_rules" {
  count                       = length(local.nsg_list)
  name                        = "${local.label}-${local.nsg_list[count.index]["nsg_name"]}-${local.nsg_list[count.index]["sg_name"]}-nsgr-${local.deployment_id}"
  priority                    = local.nsg_list[count.index]["priority"]
  direction                   = local.nsg_list[count.index]["direction"]
  access                      = local.nsg_list[count.index]["access"]
  protocol                    = local.nsg_list[count.index]["protocol"]
  source_port_range           = local.nsg_list[count.index]["source_port_range"]
  destination_port_range      = local.nsg_list[count.index]["destination_port_range"]
  source_address_prefix       = local.nsg_list[count.index]["source_address_prefix"]
  destination_address_prefix  = local.nsg_list[count.index]["destination_address_prefix"]
  resource_group_name         = data.azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.nsg[local.nsg_list[count.index]["nsg_name"]].name
  depends_on = [
    azurerm_network_security_group.nsg,
    azurerm_network_interface.vms_nics,
  ]
}

resource "azurerm_network_interface" "vms_nics" {
  for_each                      = local.vms
  name                          = "${local.created_by}-${each.key}-vm-nic-${local.deployment_id}"
  location                      = data.azurerm_resource_group.this.location
  resource_group_name           = data.azurerm_resource_group.this.name
  enable_accelerated_networking = true
  ip_configuration {
    name                          = "${local.created_by}-${each.key}-vm-nic-config-${local.deployment_id}"
    subnet_id                     = azurerm_subnet.subnets["${each.value.subnet}"].id
    public_ip_address_id          = each.value.public_ip_address ? azurerm_public_ip.vms_public_ips["${each.key}"].id : null
    private_ip_address_allocation = each.value.private_ip_address == "" ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip_address == "" ? null : each.value.private_ip_address
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-vm-nic-${local.deployment_id}" })
  depends_on = [
    azurerm_subnet.subnets,
    azurerm_public_ip.vms_public_ips
  ]
}

resource "azurerm_network_interface_security_group_association" "vms_nics_sg" {
  for_each                  = local.vms
  network_interface_id      = azurerm_network_interface.vms_nics["${each.key}"].id
  network_security_group_id = each.value.network_security_group_id
  depends_on = [
    azurerm_network_interface.vms_nics,
    azurerm_network_security_group.nsg
  ]
}

resource "azurerm_linux_virtual_machine" "vms" {
  for_each              = local.vms
  name                  = "${local.created_by}-${each.key}-vm-${local.deployment_id}"
  location              = data.azurerm_resource_group.this.location
  resource_group_name   = data.azurerm_resource_group.this.name
  network_interface_ids = [azurerm_network_interface.vms_nics["${each.key}"].id]
  size                  = each.value.size
  os_disk {
    name                 = "${local.created_by}-${each.key}-vm-os-disk-${local.deployment_id}"
    caching              = "ReadWrite"
    storage_account_type = each.value.storage_type
  }
  source_image_reference {
    publisher = each.value.publisher
    offer     = each.value.offer
    sku       = each.value.sku
    version   = each.value.version
  }
  computer_name                   = each.value.name
  admin_username                  = each.value.username
  disable_password_authentication = true
  admin_ssh_key {
    username   = each.value.username
    public_key = each.value.public_key
  }
  custom_data = base64encode(each.value.custom_data)
  tags        = merge(local.cpacket_resource_tags, { Name = "${local.label}-${each.key}-vm-${local.deployment_id}" })
  depends_on = [
    azurerm_network_interface.vms_nics
  ]
}

resource "azurerm_public_ip" "bastion_public_ip" {
  name                = "${local.created_by}-bastion-${local.deployment_id}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-bastion-${local.deployment_id}" })
}

resource "azurerm_bastion_host" "this" {
  name                = "${local.created_by}-${local.deployment_id}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku                 = "Standard"
  ip_connect_enabled  = true
  tunneling_enabled   = true
  ip_configuration {
    name                 = "${local.created_by}--nic-config-${local.deployment_id}"
    subnet_id            = azurerm_subnet.subnets["bastion"].id
    public_ip_address_id = azurerm_public_ip.bastion_public_ip.id
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-${local.deployment_id}" })
  depends_on = [
    azurerm_public_ip.bastion_public_ip,
    azurerm_subnet.subnets
  ]
}
