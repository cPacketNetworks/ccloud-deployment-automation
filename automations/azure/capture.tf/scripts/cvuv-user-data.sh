#!/bin/bash
set -ex

echo "set -o vi" >>/home/ubuntu/.bashrc
echo "set -o vi" >>/root/.bashrc

downstream_tool_ip="DOWNSTREAM_CAPTURE_IP"
capture_nic="eth0"
capture_nic_ip=$(ip a show dev "$capture_nic" | awk -F'[ /]' '/inet /{print $6}')

config_file="/home/cpacket/boot_config.toml"
touch "$config_file"
chmod a+w /home/cpacket/boot_config.toml

cat >/home/cpacket/boot_config.toml <<EOF_BOOTCFG
vm_type = "azure"
cvuv_mode = "inline"
cvuv_mirror_eth_0 = "$capture_nic"
cvuv_vxlan_id_0 = 1337
cvuv_vxlan_srcip_0 = "$capture_nic_ip"
cvuv_vxlan_remoteip_0 = "$downstream_tool_ip"
EOF_BOOTCFG

echo "boot configuration: completed"
