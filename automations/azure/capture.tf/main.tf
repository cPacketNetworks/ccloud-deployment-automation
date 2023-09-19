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

resource "random_pet" "deployment_id" {
  keepers = {
    created_by = local.created_by
    rg_cidr    = local.rg.cidr
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.label}-${local.deployment_id}"
  location = local.rg.location
  tags     = merge(local.cpacket_resource_tags, { Name = "${local.label}-${local.deployment_id}" })
}

###
# Create virtual network
###
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.label}-vnet-${local.deployment_id}"
  address_space       = [local.rg.cidr]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-vnet-${local.deployment_id}" })
}

###
# Create subnets
###
resource "azurerm_subnet" "subnets" {
  for_each             = local.subnets
  name                 = each.key == "AzureBastionSubnet" ? "AzureBastionSubnet" : "${local.label}-${each.key}-${local.deployment_id}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value.cidr]
  depends_on           = [azurerm_virtual_network.vnet]
}

resource "azurerm_subnet" "functions" {
  name                 = "functions"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.250.0/24"]
  delegation {
    name = "azure-function"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      # actions = ["Microsoft.Network/networkinterfaces/*"]
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

###
# Create subnets routes
###
resource "azurerm_route_table" "rt" {
  for_each            = local.routes
  name                = "${local.label}-${each.key}-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  depends_on = [
    azurerm_network_interface.cclears_nics,
    azurerm_network_interface.cstors_nics_public,
    azurerm_network_interface.cstors_nics_capture,
    azurerm_network_interface.vms_nics,
    azurerm_linux_virtual_machine_scale_set.cvus,
  ]
}

resource "azurerm_route" "routes" {
  for_each               = local.routes
  name                   = "${local.label}-${each.key}-${local.deployment_id}"
  resource_group_name    = azurerm_resource_group.rg.name
  route_table_name       = azurerm_route_table.rt[each.key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_type == "VirtualAppliance" ? each.value.next_hop_in_ip_address : null
}

resource "azurerm_subnet_route_table_association" "subnets_rt_association" {
  for_each       = local.routes
  subnet_id      = azurerm_subnet.subnets[each.value.subnet_association].id
  route_table_id = azurerm_route_table.rt[each.key].id
  depends_on = [
    azurerm_network_interface.vms_nics,
  ]
}

resource "azurerm_public_ip" "vms_public_ips" {
  for_each            = { for k, v in local.vms : k => v if v.public_ip_address }
  name                = "${local.label}-${each.key}-vm-public-ip-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-vm-public-ip-${local.deployment_id}" })
}

resource "azurerm_public_ip" "cstors_public_ips" {
  for_each            = { for k, v in local.cstors : k => v if v.public_ip_address }
  name                = "${local.label}-${each.key}-cstor-public-ip-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-cstor-public-ip-${local.deployment_id}" })
}

resource "azurerm_public_ip" "cclears_public_ips" {
  for_each            = { for k, v in local.cclears : k => v if v.public_ip_address }
  name                = "${local.label}-${each.key}-cclear-public-ip-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-cclear-public-ip-${local.deployment_id}" })
}

resource "azurerm_network_security_group" "nsg" {
  for_each            = local.nsg
  name                = "${local.label}-${each.key}-nsg-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg[local.nsg_list[count.index]["nsg_name"]].name
}

###
# Create network interfaces
###
resource "azurerm_network_interface" "vms_nics" {
  for_each                      = local.vms
  name                          = "${local.created_by}-${each.key}-vm-nic-${local.deployment_id}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  enable_accelerated_networking = true
  ip_configuration {
    name                          = "${local.created_by}-${each.key}-vm-nic-config-${local.deployment_id}"
    subnet_id                     = azurerm_subnet.subnets["${each.value.subnet}"].id
    public_ip_address_id          = each.value.public_ip_address ? azurerm_public_ip.vms_public_ips["${each.key}"].id : null
    private_ip_address_allocation = each.value.private_ip_address == "" ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip_address == "" ? null : each.value.private_ip_address
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-vm-nic-${local.deployment_id}" })
}

resource "azurerm_network_interface" "cstors_nics_public" {
  for_each                      = local.cstors
  name                          = "${local.created_by}-${each.key}-cstor-nic-public-${local.deployment_id}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  enable_accelerated_networking = true
  ip_configuration {
    primary                       = true
    name                          = "${local.created_by}-${each.key}-cstor-nic-public-config-${local.deployment_id}"
    subnet_id                     = azurerm_subnet.subnets["${each.value.subnet_public}"].id
    public_ip_address_id          = each.value.public_ip_address ? azurerm_public_ip.cstors_public_ips["${each.key}"].id : null
    private_ip_address_allocation = each.value.private_ip_address_public == "" ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip_address_public == "" ? null : each.value.private_ip_address_public
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-cstor-nic-public-${local.deployment_id}" })
}

resource "azurerm_network_interface" "cstors_nics_capture" {
  for_each                      = local.cstors
  name                          = "${local.created_by}-${each.key}-cstor-nic-capture-${local.deployment_id}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  enable_accelerated_networking = true
  ip_configuration {
    primary                       = false
    name                          = "${local.created_by}-${each.key}-cstor-nic-capture-config-${local.deployment_id}"
    subnet_id                     = azurerm_subnet.subnets["${each.value.subnet_capture}"].id
    private_ip_address_allocation = each.value.private_ip_address_capture == "" ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip_address_capture == "" ? null : each.value.private_ip_address_capture
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-cstor-nic-capture-${local.deployment_id}" })
}

resource "azurerm_network_interface" "cclears_nics" {
  for_each                      = local.cclears
  name                          = "${local.created_by}-${each.key}-cclear-nic-${local.deployment_id}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  enable_accelerated_networking = true
  ip_configuration {
    name                          = "${local.created_by}-${each.key}-cclear-nic-config-${local.deployment_id}"
    subnet_id                     = azurerm_subnet.subnets["${each.value.subnet}"].id
    public_ip_address_id          = each.value.public_ip_address ? azurerm_public_ip.cclears_public_ips["${each.key}"].id : null
    private_ip_address_allocation = each.value.private_ip_address == "" ? "Dynamic" : "Static"
    private_ip_address            = each.value.private_ip_address == "" ? null : each.value.private_ip_address
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-cclear-nic-${local.deployment_id}" })
}

###
# Connect the security group to the network interface
###
resource "azurerm_network_interface_security_group_association" "vms_nics_sg" {
  for_each                  = local.vms
  network_interface_id      = azurerm_network_interface.vms_nics["${each.key}"].id
  network_security_group_id = each.value.network_security_group_id
  depends_on                = [azurerm_network_interface.vms_nics]
}

resource "azurerm_network_interface_security_group_association" "cstors_nics_public_sg" {
  for_each                  = local.cstors
  network_interface_id      = azurerm_network_interface.cstors_nics_public["${each.key}"].id
  network_security_group_id = each.value.network_security_group_id
  depends_on                = [azurerm_network_interface.cstors_nics_public, azurerm_network_interface.cstors_nics_capture]
}

resource "azurerm_network_interface_security_group_association" "cstors_nics_capture_sg" {
  for_each                  = local.cstors
  network_interface_id      = azurerm_network_interface.cstors_nics_capture["${each.key}"].id
  network_security_group_id = each.value.network_security_group_id
  depends_on                = [azurerm_network_interface.cstors_nics_public, azurerm_network_interface.cstors_nics_capture]
}

resource "azurerm_network_interface_security_group_association" "cclears_nics_sg" {
  for_each                  = local.cclears
  network_interface_id      = azurerm_network_interface.cclears_nics["${each.key}"].id
  network_security_group_id = each.value.network_security_group_id
  depends_on                = [azurerm_network_interface.cclears_nics]
}

resource "azurerm_lb" "lbs" {
  for_each            = local.lbs
  name                = "${local.created_by}-${each.key}-lb-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  frontend_ip_configuration {
    name                                               = "${local.created_by}-${each.key}-lb-frontend-${local.deployment_id}"
    subnet_id                                          = each.value.public_ip_address ? null : azurerm_subnet.subnets["${each.value.subnet}"].id
    private_ip_address                                 = each.value.public_ip_address ? null : each.value.private_ip_address
    private_ip_address_allocation                      = each.value.public_ip_address ? null : "Static"
  }
  sku  = each.value.sku
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-${each.key}-lb-${local.deployment_id}" })
}

resource "azurerm_lb_backend_address_pool" "lbs_backend_pool" {
  for_each        = local.lbs
  name            = "${local.created_by}-${each.key}-lb-backend-pool-${local.deployment_id}"
  loadbalancer_id = azurerm_lb.lbs["${each.key}"].id
}

resource "azurerm_lb_probe" "lb_probs" {
  for_each            = local.lbs
  name                = "${local.created_by}-${each.key}-lb-probe-${local.deployment_id}"
  loadbalancer_id     = azurerm_lb.lbs["${each.key}"].id
  port                = each.value.probe_port
  probe_threshold     = each.value.probe_threshold
  interval_in_seconds = each.value.interval_in_seconds
  number_of_probes    = each.value.number_of_probes
  depends_on          = [azurerm_lb.lbs]
}

resource "azurerm_lb_rule" "lbs_rules" {
  for_each                       = local.lbs
  name                           = "${local.created_by}-${each.key}-lb-rule-${local.deployment_id}"
  loadbalancer_id                = azurerm_lb.lbs["${each.key}"].id
  protocol                       = each.value.protocol
  frontend_ip_configuration_name = "${local.created_by}-${each.key}-lb-frontend-${local.deployment_id}"
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lbs_backend_pool["${each.key}"].id]
  probe_id                       = azurerm_lb_probe.lb_probs["${each.key}"].id
  enable_tcp_reset               = true
  depends_on                     = [azurerm_lb_probe.lb_probs]
}

resource "azurerm_linux_virtual_machine" "vms" {
  for_each              = local.vms
  name                  = "${local.created_by}-${each.key}-vm-${local.deployment_id}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
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
  depends_on  = [azurerm_network_interface.vms_nics, azurerm_network_interface_security_group_association.vms_nics_sg]
}

resource "azurerm_linux_virtual_machine_scale_set" "cvus" {
  name                = "${local.created_by}-${local.deployment_id}-cvu"
  instances           = local.cvus.instances
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = local.cvus.size
  admin_ssh_key {
    username   = local.cvus.username
    public_key = local.cvus.public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = local.cvus.storage_type
  }
  network_interface {
    name                          = "${local.created_by}-${local.deployment_id}-cvu-nic-public"
    primary                       = false
    enable_accelerated_networking = true
    enable_ip_forwarding          = local.cvus.enable_ip_forwarding_public
    network_security_group_id     = local.cvus.network_security_group_id_public
    ip_configuration {
      name      = "${local.created_by}-${local.deployment_id}-cvu-nic-public-config"
      primary   = true
      subnet_id = local.cvus.subnet_id_public
      public_ip_address {
        name = "${local.label}-cvu-public-ip-${local.deployment_id}"
      }
    }
  }
  network_interface {
    name                          = "${local.created_by}-${local.deployment_id}-cvu-nic-capture"
    primary                       = true
    enable_accelerated_networking = true
    enable_ip_forwarding          = local.cvus.enable_ip_forwarding_capture
    network_security_group_id     = local.cvus.network_security_group_id_capture
    ip_configuration {
      name                                   = "${local.created_by}-${local.deployment_id}-cvu-capture-config"
      primary                                = true
      subnet_id                              = local.cvus.subnet_id_capture
      load_balancer_backend_address_pool_ids = [local.cvus.load_balancer_backend_address_pool_id]
    }
  }
  source_image_id      = local.cvus.image_id
  computer_name_prefix = local.cvus.name
  admin_username       = local.cvus.username
  custom_data          = base64encode(local.cvus.custom_data)
  health_probe_id      = local.cvus.health_probe_id
  overprovision = false
  
  automatic_instance_repair {
    enabled      = true
    grace_period = local.cvus.grace_period
  }


  tags = merge(local.cpacket_resource_tags, { name = "${local.label}-cvu-${local.deployment_id}" })
  depends_on = [
    azurerm_lb.lbs,
    azurerm_lb_probe.lb_probs,
    azurerm_lb_rule.lbs_rules,
    azurerm_linux_function_app.this,
    azurerm_eventgrid_system_topic.this,
    null_resource.remaining,
  ]
}

resource "azurerm_monitor_autoscale_setting" "cvus_capture" {
  name                = "${local.created_by}-cvu-autoscale-${local.deployment_id}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.cvus.id
  profile {
    name = "${local.created_by}-cvu-autoscale-profile-${local.deployment_id}"
    capacity {
      default = local.cvus.autoscale_defult
      minimum = local.cvus.autoscale_min
      maximum = local.cvus.autoscale_max
    }
    rule {
      metric_trigger {
        metric_name        = "Network in Total"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.cvus.id
        time_grain         = local.cvus.autoscale_up_time_grain
        statistic          = "Average"
        time_window        = local.cvus.autoscale_up_time_window
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = local.cvus.autoscale_up_threshhold
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
    rule {
      metric_trigger {
        metric_name        = "Network in Total"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.cvus.id
        time_grain         = local.cvus.autoscale_down_time_grain
        statistic          = "Average"
        time_window        = local.cvus.autoscale_down_time_window
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = local.cvus.autoscale_down_threshhold
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
  tags = merge(local.cpacket_resource_tags, { name = "${local.label}-cvu-autoscale-${local.deployment_id}" })
}

# TODO: This resource is frozen and will continue to be available throughtout 3.x
#
# We are unable to use the newer azurerm_linux_virtual_machine because it will not create
# and attach the data disks before starting causing issues with admin_app.service allocating data disks.
#
# We are unable to pause admin_app.service using cloud-init.
resource "azurerm_virtual_machine" "cstors" {
  for_each                      = local.cstors
  name                          = "${local.created_by}-${each.key}-cstor-${local.deployment_id}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  primary_network_interface_id  = azurerm_network_interface.cstors_nics_public["${each.key}"].id
  network_interface_ids         = [azurerm_network_interface.cstors_nics_capture["${each.key}"].id, azurerm_network_interface.cstors_nics_public["${each.key}"].id]
  vm_size                       = each.value.size
  delete_os_disk_on_termination = true
  storage_os_disk {
    name              = "${local.created_by}-${each.key}-stor-os-disk-${local.deployment_id}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = each.value.storage_type
  }
  storage_image_reference {
    id = each.value.image_id
  }
  delete_data_disks_on_termination = true
  dynamic "storage_data_disk" {
    for_each = range(each.value.data_disks)
    content {
      name              = "${local.created_by}-${each.key}-stor-data-disk-${storage_data_disk.value}-${local.deployment_id}"
      create_option     = "Empty"
      caching           = "ReadWrite"
      managed_disk_type = each.value.storage_type
      disk_size_gb      = each.value.data_disks_size
      lun               = storage_data_disk.value + 1
    }
  }
  tags = merge(local.cpacket_resource_tags, { name = "${local.label}-${each.key}-stor-${local.deployment_id}" })
  os_profile {
    computer_name  = each.value.name
    admin_username = each.value.username
    custom_data    = base64encode(each.value.custom_data)
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = each.value.public_key
      path     = "/home/${each.value.username}/.ssh/authorized_keys"
    }
  }
  depends_on = [
    azurerm_network_interface.cstors_nics_public,
    azurerm_network_interface.cstors_nics_capture,
    azurerm_network_interface_security_group_association.cstors_nics_public_sg,
    azurerm_network_interface_security_group_association.cstors_nics_capture_sg,
  ]
}

resource "azurerm_linux_virtual_machine" "cclears" {
  for_each              = local.cclears
  name                  = "${local.created_by}-${each.key}-cclear-${local.deployment_id}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.cclears_nics["${each.key}"].id]
  size                  = each.value.size
  os_disk {
    name                 = "${local.created_by}-${each.key}-cclear-os-disk-${local.deployment_id}"
    caching              = "ReadWrite"
    storage_account_type = each.value.storage_type
  }
  source_image_id                 = each.value.image_id
  computer_name                   = each.value.name
  admin_username                  = each.value.username
  disable_password_authentication = true
  admin_ssh_key {
    username   = each.value.username
    public_key = each.value.public_key
  }
  custom_data = each.value.custom_data == null ? null : base64encode(each.value.custom_data)
  tags = merge(local.cpacket_resource_tags,
    {
      Name                    = "${local.label}-${each.key}-cclear-${local.deployment_id}"
      "cpacket:ApplianceType" = "cClear-V"
    }
  )
  depends_on = [azurerm_network_interface.cclears_nics, azurerm_network_interface_security_group_association.cclears_nics_sg]
}

resource "azurerm_public_ip" "bastion_public_ip" {
  name                = "${local.created_by}-bastion-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.cpacket_resource_tags, { Name = "${local.label}-bastion-${local.deployment_id}" })
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${local.created_by}-${local.deployment_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  ip_connect_enabled  = true
  tunneling_enabled   = true
  ip_configuration {
    name                 = "${local.created_by}--nic-config-${local.deployment_id}"
    subnet_id            = azurerm_subnet.subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.bastion_public_ip.id
  }
  tags = merge(local.cpacket_resource_tags, { Name = "${local.label}-${local.deployment_id}" })
}

// Azure function app registration
resource "azurerm_storage_account" "this" {
  name                     = local.registration_function_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# This should be 'Premium'
resource "azurerm_service_plan" "this" {
  name                = local.registration_function_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  # reserved            = true
  # kind                = "functionapp"
  sku_name = "EP1" # Required for the Function App to talk to the vnet (and the appliances)
}

resource "azurerm_linux_function_app" "this" {
  name                = local.registration_function_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.this.id
  virtual_network_subnet_id  = azurerm_subnet.functions.id

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME           = "python"
    WEBSITE_RUN_FROM_PACKAGE           = "0"
    APPLIANCE_HTTP_BASIC_AUTH_PASSWORD = var.web_password
    APPINSIGHTS_INSTRUMENTATIONKEY     = azurerm_application_insights.this.instrumentation_key
  }

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_linux_virtual_machine.cclears
  ]
}

# Notifies the Azure function that events in the resource group have happened.
# See https://stackoverflow.com/questions/70880703/creation-of-system-topic-failed-while-creating-event-subscription-in-azure-maps/70940961#70940961
# --location should be specific to the resource group, but this fails with:
#   System topic's location must match with location of the source resource <resource group id>
resource "azurerm_eventgrid_system_topic" "this" {
  name                   = var.event_grid_topic_name
  resource_group_name    = azurerm_resource_group.rg.name
  location               = "global"
  source_arm_resource_id = azurerm_resource_group.rg.id
  # We only care about events from our resource group.
  topic_type = "Microsoft.Resources.ResourceGroups"
}

# # This would work if we could get the Azure function to work.
# resource "azurerm_eventgrid_system_topic_event_subscription" "this" {
#   name                = "scaling-events"
#   system_topic        = azurerm_eventgrid_system_topic.this.id
#   resource_group_name = azurerm_resource_group.rg.name
# 
#   azure_function_endpoint {
#     function_id = azurerm_function_app_function.this.id
#   }
# }

# This is a hack to get the Azure function to work.
# We call a Bash script that deploys the Azure function via the 'func' core CLI tool.
# We also create a event subscription that sends the events to the Azure function.
resource "null_resource" "remaining" {
  provisioner "local-exec" {
    working_dir = "${path.module}/functionapp"
    command     = "./deploy.sh"
    environment = {
      RESOURCE_GROUP        = azurerm_resource_group.rg.name
      FUNCTION_NAME         = azurerm_linux_function_app.this.name
      EVENT_GRID_TOPIC_NAME = var.event_grid_topic_name
    }
  }

  depends_on = [
    azurerm_linux_function_app.this
  ]
}

resource "azurerm_application_insights" "this" {
  name                = local.registration_function_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
}

# The 'contributor' role is probably too permissive.
# Maybe 'reader' is better?
data "azurerm_subscription" "primary" {}
resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}
