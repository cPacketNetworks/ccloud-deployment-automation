#!/bin/bash
set -e
set -x

# Wait until we are connected to the internet.
until wget -q --spider http://google.com; do
  sleep 10
done
apt-get update
apt-get upgrade -y
apt-get autoremove -y
apt-get install -y iputils-ping bash-completion iputils-tracepath vim tree iperf3 sockperf
echo "set -o vi" >>/home/ubuntu/.bashrc
echo "set -o vi" >>/root/.bashrc
reboot
