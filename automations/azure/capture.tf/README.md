# register appliances with cClear-V 

> Register appliances with cClear-V as they are added/removed from the VMSS.

## Overview

This Terraform module deploys cVu-Vs in VMSS along with cClear-V.
The instances of cVu-V are registered/de-registered with cClear-V as they are added/removed from the VMSS.

## Terraform

Deploy the Terraform module as usual,

```bash
terraform init
terraform apply
```

To supply the required variables, create a `*.auto.tfvars` file, for instance

```hcl
cclearv_image = "/subscriptions/93004638-8c6b-4e33-ba58-946afd57efdf/resourceGroups/mbright-ga-images/providers/Microsoft.Compute/images/cclear-v-22.3.316"
cstorv_image  = "/subscriptions/93004638-8c6b-4e33-ba58-946afd57efdf/resourceGroups/mbright-ga-images/providers/Microsoft.Compute/images/cstor-v-22.3.138"
cvuv_image    = "/subscriptions/93004638-8c6b-4e33-ba58-946afd57efdf/resourceGroups/mbright-ga-images/providers/Microsoft.Compute/images/cvu-v-22.3.311"
web_password  = "something"
owner         = "jdoe@cpacketnetworks.com"
```
