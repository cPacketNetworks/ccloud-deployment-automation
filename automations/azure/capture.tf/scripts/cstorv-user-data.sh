#!/bin/bash
set -ex

capture_nic_ip="CSTORV_CAPTURE_IP"
capture_nic="eth1"
management_nic_ip="MANAGEMENT_NIC_IP"
management_nic="eth0"

echo "set -o vi" >>/home/ubuntu/.bashrc
echo "set -o vi" >>/root/.bashrc

config_file="/home/cpacket/boot_config.toml"
touch "$config_file"
chmod a+w /home/cpacket/boot_config.toml

cat >/home/cpacket/boot_config.toml <<EOF_BOOTCFG
vm_type = "azure"
decap_mode = "vxlan"
capture_mode =  "libpcap"
eth_dev  = "$capture_nic"
capture_nic_index = 0
capture_nic_eth = "eth0"
capture_nic_ip = "$capture_nic_ip"
management_nic_eth = "$management_nic"
management_nic_ip = "$management_nic_ip"
num_pcap_bufs = 2
EOF_BOOTCFG

echo "boot configuration: completed"
