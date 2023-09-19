# Verification and sythetic traffic

After the capture network is deployed, you can direct traffic to it.
To verify that the capture network is working, you can set up test infrastructure to generate synthetic traffic and direct it to the capture network load balancer.

## Test infrastructure

The test infrastructure consists of 2 VMs in separate subnets that are configured with their next hops as the capture network load balancer.

To deploy the test infrastructure, obtain the terraform module:

```bash
git clone https://github.com/cPacketNetworks/ccloud-deployment-automation
cd cloud-deployment-automation/automations/azure/synthetic-traffic
```

The following are example parameters to supply to the module:

```hcl
resource_group = "capture-net"
vnet_name      = "cpacket-xyz-vnet"
owner          = "jsmith@your-company.com"
lb_ip          = "10.20.0.5"
```

`lb_ip` is the IP address of the load balancer in the capture network.
This will be the next hop in the route tables of the subnets that house the VMs that generate and receive the synthetic network traffic.

While in the directory containing the Terraform files, configure the above parameters and put them in a file named `synthetic-traffic.auto.tfvars` and run the following commands:

```bash
terraform init
terraform apply
```
