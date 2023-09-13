# Synthetic traffic

This Terraform module deploys a couple of VMs in separate subnets in the specified resource group and VNET.
The module is intended to be used for testing purposes.
Routes are added to the subnets so that the network traffic can be inspected by the ccloud appliances.

The following are example parameters to supply to the module:

```hcl
resource_group = "capture-net"
vnet_name      = "cpacket-xyz-vnet"
owner          = "jsmith@cpacketnetworks.com"
lb_ip          = "10.20.0.5"
```

`lb_ip` is the IP address of the load balancer that is the next hop used in the route tables of the subnets that house the VMs.
