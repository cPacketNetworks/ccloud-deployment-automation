variable "web_password" {
  description = "Password for appliance HTTP Basic Auth"
}

variable "cvuv_image" {
  type = string
}

variable "cstorv_image" {
  type = string
}

variable "cclearv_image" {
  type = string
}

variable "event_grid_topic_name" {
  type    = string
  default = "rgevents"
}

variable "functionapp_name" {
  description = "Name of the function"
  default     = "register"
}

variable "label" {
  description = "Descriptor for the deployment"
  default     = ""
}

variable "owner" {
  description = "email of owner of the deployment"
  default     = null
  nullable    = true
}

variable "deployment_id" {
  description = "unique identifier for the deployment"
  default     = ""
}

# key pair to use
variable "key_pair" {
  description = "SSH key pair name to access appliances"
  default     = "~/.ssh/id_rsa.pub"
}

locals {
  deployment_id              = var.deployment_id != "" ? var.deployment_id : "${random_pet.deployment_id.id}"
  registration_function_name = format("%s%s", var.functionapp_name, replace(local.deployment_id, "-", ""))
  created_by                 = trimsuffix(regex(".*@", data.azuread_user.current_user.user_principal_name), "@")
  label                      = var.label != "" ? var.label : local.created_by
  cpacket_resource_tags = {
    "cpacket:DeploymentID" = var.deployment_id != "" ? var.deployment_id : local.deployment_id
    "cpacket:CreatedBy"    = local.created_by
    "owner"                = var.owner
  }
  instance_sizes = {
    ubuntu       = "Standard_D2s_v5"
    cvu          = "Standard_D2s_v5"
    cstor        = "Standard_D4s_v5"
    cclear       = "Standard_D2s_v5"
    storage_type = "Standard_LRS"
  }
  cstors_disk_info = {
    data_disks      = 6
    data_disks_size = 128
    storage_type    = "Premium_LRS"
  }
  ubuntu_image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  rg = {
    location = "eastus2"
    cidr     = "10.0.0.0/16"
  }
  subnets = {
    public = {
      name = "public"
      cidr = "10.0.0.0/24"
    }
    workload_a = {
      name = "workload_a"
      cidr = "10.0.1.0/24"
    }
    workload_b = {
      name = "workload_b"
      cidr = "10.0.2.0/24"
    }
    capture = {
      name = "capture"
      cidr = "10.0.253.0/24"
    }
    AzureBastionSubnet = {
      name = "azure_tools"
      cidr = "10.0.254.0/24"
    }
  }
  gwlbs = {
  }
  lbs = {
    cvu = {
      sku                 = "Standard"
      subnet              = local.subnets.capture.name
      private_ip_address  = "10.0.253.10"
      public_ip_address   = false
      protocol            = "All"
      frontend_port       = "0"
      backend_port        = "0"
      gwlb_frontend_id    = null
      probe_port          = 80
      probe_threshold     = 1
      interval_in_seconds = 15 # default 15
      number_of_probes    = 2  # default 2
    }
  }
  routes = {
    workload_a_rt = {
      name                   = "workload_a_rt"
      subnet_association     = local.subnets.workload_a.name
      address_prefix         = local.subnets.workload_b.cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = azurerm_lb.lbs["cvu"].frontend_ip_configuration[0].private_ip_address
    }
    workload_b_rt = {
      name                   = "workload_b_rt"
      subnet_association     = local.subnets.workload_b.name
      address_prefix         = local.subnets.workload_a.cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = azurerm_lb.lbs["cvu"].frontend_ip_configuration[0].private_ip_address
    }
  }
  # unable to use data created in a local when creating the local
  vms_info = {
    ubuntu_0 = {
      private_ip_address = "10.0.1.10"
    }
    ubuntu_1 = {
      private_ip_address = "10.0.2.10"
    }
  }
  vms = {
    ubuntu_0 = {
      name                      = "ubuntu-0" # name cannot have '_' in the hostname
      username                  = "ubuntu"
      subnet                    = local.subnets.workload_a.name
      public_ip_address         = false
      private_ip_address        = local.vms_info.ubuntu_0.private_ip_address
      network_security_group_id = azurerm_network_security_group.nsg["workload"].id
      public_key                = file(var.key_pair)
      size                      = local.instance_sizes.ubuntu
      custom_data               = file("scripts/app-user-data.sh")
      storage_type              = local.instance_sizes.storage_type
      publisher                 = local.ubuntu_image.publisher
      offer                     = local.ubuntu_image.offer
      sku                       = local.ubuntu_image.sku
      version                   = local.ubuntu_image.version
    }
    ubuntu_1 = {
      name                      = "ubuntu-1" # name cannot have '_' in the hostname
      username                  = "ubuntu"
      subnet                    = local.subnets.workload_b.name
      public_ip_address         = false
      private_ip_address        = local.vms_info.ubuntu_1.private_ip_address
      network_security_group_id = azurerm_network_security_group.nsg["workload"].id
      public_key                = file(var.key_pair)
      size                      = local.instance_sizes.ubuntu
      custom_data               = file("scripts/app-user-data.sh")
      storage_type              = local.instance_sizes.storage_type
      publisher                 = local.ubuntu_image.publisher
      offer                     = local.ubuntu_image.offer
      sku                       = local.ubuntu_image.sku
      version                   = local.ubuntu_image.version
    }
  }
  cvus = {
    instances                             = 3
    name                                  = "cvu" # name cannot have '_' in the hostname
    username                              = "ubuntu"
    enable_ip_forwarding_public           = false
    enable_ip_forwarding_capture          = true
    network_security_group_id_public      = azurerm_network_security_group.nsg["cvu_public"].id
    network_security_group_id_capture     = azurerm_network_security_group.nsg["cvu_capture"].id
    load_balancer_backend_address_pool_id = azurerm_lb_backend_address_pool.lbs_backend_pool["cvu"].id
    subnet_id_public                      = azurerm_subnet.subnets["public"].id
    subnet_id_capture                     = azurerm_subnet.subnets["capture"].id
    public_key                            = file(var.key_pair)
    size                                  = local.instance_sizes.cvu
    custom_data                           = replace(file("scripts/cvuv-user-data.sh"), "DOWNSTREAM_CAPTURE_IP", local.cstors_info.cstor_0.private_ip_address_capture)
    storage_type                          = local.instance_sizes.storage_type
    image_id                              = var.cvuv_image
    health_probe_id                       = azurerm_lb_probe.lb_probs["cvu"].id
    grace_period                          = "PT10M" # time given in ISO 8601 format
    autoscale_defult                      = 3
    autoscale_min                         = 3
    autoscale_max                         = 5
    autoscale_up_threshhold               = 9663676416 # Network bandwith in bytes (12GB * .75) i.e. 12884901888 * .75 = 9663676416
    autoscale_up_time_grain               = "PT1M"
    autoscale_up_time_window              = "PT5M"
    autoscale_down_threshhold             = 3221225472 # Network bandwith in bytes (12GB * .25) i.e. 12884901888 * .25 = 3221225472
    autoscale_down_time_grain             = "PT1M"
    autoscale_down_time_window            = "PT5M"
  }
  # unable to use data created in a local when creating the local
  cstors_info = {
    cstor_0 = {
      private_ip_address_public  = "10.0.0.100"
      private_ip_address_capture = "10.0.253.100"
    }
  }
  cstors = {
    cstor_0 = {
      name                       = "cstor-0" # name cannot have '_' in the hostname
      username                   = "ubuntu"
      subnet_public              = local.subnets.public.name
      subnet_capture             = local.subnets.capture.name
      public_ip_address          = true
      private_ip_address_public  = local.cstors_info.cstor_0.private_ip_address_public
      private_ip_address_capture = local.cstors_info.cstor_0.private_ip_address_capture
      network_security_group_id  = azurerm_network_security_group.nsg["cstor"].id
      public_key                 = file(var.key_pair)
      size                       = local.instance_sizes.cstor
      custom_data                = replace(replace(file("scripts/cstorv-user-data.sh"), "CSTORV_CAPTURE_IP", local.cstors_info.cstor_0.private_ip_address_capture), "MANAGEMENT_NIC_IP", local.cstors_info.cstor_0.private_ip_address_public)
      storage_type               = local.instance_sizes.storage_type
      image_id                   = var.cstorv_image
      data_disks                 = local.cstors_disk_info.data_disks
      data_disks_size            = local.cstors_disk_info.data_disks_size
    }
  }
  # unable to use data created in a local when creating the local
  cclears_info = {
    cclear_0 = {
      private_ip_address = "10.0.0.200"
    }
  }
  cclears = {
    cclear_0 = {
      name                      = "clear-0" # name cannot have '_' in the hostname
      username                  = "ubuntu"
      subnet                    = local.subnets.public.name
      public_ip_address         = true
      private_ip_address        = local.cclears_info.cclear_0.private_ip_address
      network_security_group_id = azurerm_network_security_group.nsg["cclear"].id
      public_key                = file(var.key_pair)
      size                      = local.instance_sizes.cclear
      custom_data               = null
      storage_type              = local.instance_sizes.storage_type
      image_id                  = var.cclearv_image
    }
  }
  nsg = {
    workload = {
      internal = {
        name                       = "internal"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
    }
    cvu_public = {
      internal = {
        name                       = "internal"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      http = {
        name                       = "http"
        priority                   = 102
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
      https = {
        name                       = "https"
        priority                   = 103
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    }
    cvu_capture = {
      internal = {
        name                       = "internal"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
    }
    cstor = {
      internal = {
        name                       = "internal"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      http = {
        name                       = "http"
        priority                   = 102
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
      https = {
        name                       = "https"
        priority                   = 103
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    }
    cclear = {
      internal = {
        name                       = "internal"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
      }
      http = {
        name                       = "http"
        priority                   = 102
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
      https = {
        name                       = "https"
        priority                   = 103
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
      ssh = {
        name                       = "ssh"
        priority                   = 104
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      }
    }
  }
}
