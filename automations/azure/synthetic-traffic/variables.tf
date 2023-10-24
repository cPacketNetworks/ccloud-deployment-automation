variable "vnet_name" {
  type = string
}

variable "bastion_subnet_cidr" {
  type    = string
  default = "10.0.254.0/24"
}

variable "workloadA_subnet_cidr" {
  type    = string
  default = "10.0.20.0/24"
}

variable "workload_a_ip" {
  type    = string
  default = "10.0.20.10"
}

variable "workloadB_subnet_cidr" {
  type    = string
  default = "10.0.21.0/24"
}

variable "workload_b_ip" {
  type    = string
  default = "10.0.21.10"
}

variable "lb_ip" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "label" {
  description = "Descriptor for the deployment"
  default     = ""
}

variable "owner" {
  description = "email of owner of the deployment"
}

variable "deployment_id" {
  description = "unique identifier for the deployment"
  default     = null
}

variable "key_pair" {
  description = "SSH key pair name to access traffic generation hosts"
  default     = "~/.ssh/id_rsa.pub"
}

locals {
  deployment_id = var.deployment_id != null ? var.deployment_id : "${random_pet.deployment_id.id}"
  created_by    = trimsuffix(regex(".*@", data.azuread_user.current_user.user_principal_name), "@")
  label         = var.label != "" ? var.label : local.created_by
  cpacket_resource_tags = {
    "cpacket:DeploymentID" = local.deployment_id
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
  ubuntu_image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  subnets = {
    workload_a = {
      name = "workload_a"
      cidr = var.workloadA_subnet_cidr
    }
    workload_b = {
      name = "workload_b"
      cidr = var.workloadB_subnet_cidr
    }
    bastion = {
      name = "AzureBastionSubnet"
      cidr = var.bastion_subnet_cidr
    }
  }
  routes = {
    workload_a_rt = {
      name                   = "workload_a_rt"
      subnet_association     = local.subnets.workload_a.name
      address_prefix         = local.subnets.workload_b.cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.lb_ip
    }
    workload_b_rt = {
      name                   = "workload_b_rt"
      subnet_association     = local.subnets.workload_b.name
      address_prefix         = local.subnets.workload_a.cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.lb_ip
    }
  }
  vms_info = {
    ubuntu_0 = {
      private_ip_address = var.workload_a_ip
    }
    ubuntu_1 = {
      private_ip_address = var.workload_b_ip
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
  }
}
