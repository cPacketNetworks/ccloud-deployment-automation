output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "deployment_id" {
  value = local.deployment_id
}

output "public_vms_ip_address" {
  value = [for ip in azurerm_public_ip.vms_public_ips : ip.ip_address]
}

output "public_cstors_ip_address" {
  value = [for ip in azurerm_public_ip.cstors_public_ips : ip.ip_address]
}

output "public_cclears_ip_address" {
  value = [for ip in azurerm_public_ip.cclears_public_ips : ip.ip_address]
}

output "bastion_connections_to_vms" {
  value = [for vm in azurerm_linux_virtual_machine.vms :
    join(" ",
      [
        "az network bastion ssh ",
        "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--auth-type ssh-key ",
        "--username ubuntu ",
        "--ssh-key", trimsuffix(var.key_pair, ".pub"), "\n"
      ]
    )
  ]
}

output "bastion_connections_to_cstors" {
  value = [for vm in azurerm_virtual_machine.cstors :
    join(" ",
      [
        "az network bastion ssh ", "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--auth-type ssh-key ",
        "--username ubuntu ",
        "--ssh-key", trimsuffix(var.key_pair, ".pub"), "\n"
      ]
    )
  ]
}

output "bastion_connections_to_cclears" {
  value = [for vm in azurerm_linux_virtual_machine.cclears :
    join(" ",
      [
        "az network bastion ssh ", "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--auth-type ssh-key ",
        "--username ubuntu ",
        "--ssh-key", trimsuffix(var.key_pair, ".pub"), "\n"
      ]
    )
  ]
}

output "bastion_tunnel_to_vms" {
  value = [for vm in azurerm_linux_virtual_machine.vms :
    join(" ",
      [
        "az network bastion tunnel ",
        "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--resource-port 22 ",
        "--port 2222 &\n"
      ]
    )
  ]
}

output "bastion_tunnel_to_cstors" {
  value = [for vm in azurerm_virtual_machine.cstors :
    join(" ",
      [
        "az network bastion tunnel ",
        "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--resource-port 22 ",
        "--port 2222 &\n"
      ]
    )
  ]
}

output "bastion_tunnel_to_cclears" {
  value = [for vm in azurerm_linux_virtual_machine.cclears :
    join(" ",
      [
        "az network bastion tunnel ",
        "--name ${azurerm_bastion_host.bastion.name} ",
        "--resource-group ${azurerm_resource_group.rg.name} ",
        "--target-resource-id ${vm.id} ",
        "--resource-port 22 ",
        "--port 2222 &\n"
      ]
    )
  ]
}

output "tunnel_connecction_vms" {
  value = "ssh -p 2222 ubuntu@localhost\nscp -P 2222 -r * azureuser@localhost:~/"
}

output "tunnel_connecction_cstors_cclears" {
  value = "ssh -p 2222 ubuntu@localhost\nscp -P 2222 -r * ubuntu@localhost:~/"
}
