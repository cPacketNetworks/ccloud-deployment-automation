output "bastion_connections_to_vms" {
  value = [for vm in azurerm_linux_virtual_machine.vms :
    join(" ",
      [
        "az network bastion ssh ",
        "--name ${azurerm_bastion_host.this.name} ",
        "--resource-group ${data.azurerm_resource_group.this.name} ",
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
        "--name ${azurerm_bastion_host.this.name} ",
        "--resource-group ${data.azurerm_resource_group.this.name} ",
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
