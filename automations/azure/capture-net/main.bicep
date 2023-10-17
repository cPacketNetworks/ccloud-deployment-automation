// Purpose: Deploys the resources for the UI based inputs that are gathered/defined in the associated createUIDefinition.json.

// Parameters - start
// These are passed in from createUIDefinition.json as the template's "payload".
// This is the interactive application that runs in the context of the Azure portal. 
// See the "outputs" section of createUIDefinition.json
//
// These can also be passed in from the command line when running with the Azure CLI:
//
// az deployment group create \
//   --name "$deployment" \
//   --resource-group "$resource_group" \
//   --template-file "$template" \
//   --parameters "$parameters" \
//   --verbose --debug
//
// where $parameters is a JSON file containing the parameters to pass in

param location string

param deploymentId string
param sshPublicKey string
param adminUser string = 'ubuntu'
param virtualNetwork object

param cclearvName string = 'cClear-V'
param cclearvVmSize string = 'Standard_D4s_v5'
param cclearvVmImageId string

param lbName string
param vmssName string
param vmssVmSize string
param cvuvVmImageId string
param vmssMin int
param vmssMax int

param cstorvEnable bool
param cstorvName string
param cstorvVmImageId string
param cstorvVmSize string
param cstorvVmNumDisks int = 2
param cstorvVmDiskSize int = 500
param cstorvDataDiskDeleteOption string = 'Detach'
param cstorvCaptureIpAddress string

// cvuv downstream tool IPs - must go into generated user-data
param downstreamTools string

// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/tag-support
// https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/tag-resources-bicep 
param tags object

// Parameters - end
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Variables - start

// Ensure 60 is a reasonable value - guessing between 60 and 300.
// see: https://learn.microsoft.com/en-us/azure/templates/microsoft.network/loadbalancers?pivots=deployment-language-bicep#backendaddresspoolpropertiesformat
// var lbDrainPeriodInSecs = 60
// var lbIdleTimeoutInMinutes = 5
var lbBePoolName = '${lbName}-backend'
var lbPoolId = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
var lbProbeName = '${lbName}-probe'
var lbProbeId = resourceId('Microsoft.Network/loadBalancers/probes', lbName, lbProbeName)

var vmssInstRepairGracePeriod = 'PT10M'

// TODO: will probably need to add these to the UI and bring in as params.
var autoscaleUpThreshhold = 10000000 // 10 MBytes
var autoscaleUpTimeGrain = 'PT1M'
var autoscaleUpTimeWindow = 'PT5M'
var autoscaleUpCooldown = 'PT1M'
var autoscaleDownThreshhold = 2500000 // 2.5 MBytes
var autoscaleDownTimeGrain = 'PT1M'
var autoscaleDownTimeWindow = 'PT5M'
var autoscaleDownCooldown = 'PT1M'

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUser}/.ssh/authorized_keys'
        keyData: sshPublicKey
      }
    ]
  }
}

var cvuv_cloud_init_template = '''
#!/bin/bash
set -ex

echo "set -o vi" >>/home/ubuntu/.bashrc
echo "set -o vi" >>/root/.bashrc

bootconfig_file="/home/cpacket/boot_config.toml"

# Comma-separated list of IPV4 addresses
downstream_tools="DOWNSTREAM_CAPTURE_IPS"

# Convert the comma-separated list into an array
IFS=',' read -r -a downstream_tool_addresses <<<"$(echo "$downstream_tools" | tr -d '[:space:]')"

capture_nic="eth0"
capture_nic_ip=$(ip a show dev "$capture_nic" | awk -F'[ /]' '/inet /{print $6}')

touch "$bootconfig_file"
chmod a+w "$bootconfig_file"

cat >"$bootconfig_file" <<BOOTCFG_HEADER
vm_type = "azure"
cvuv_mode = "inline"
cvuv_mirror_eth_0 = "$capture_nic"
BOOTCFG_HEADER

for tools_index in "${!downstream_tool_addresses[@]}"; do
  name_index=$((tools_index))
  leet_index=$((tools_index + 1337))
  cat >>"$bootconfig_file" <<ADDITIONAL_TOOLS
cvuv_vxlan_id_${name_index} = ${leet_index}
cvuv_vxlan_srcip_${name_index} = "$capture_nic_ip"
cvuv_vxlan_remoteip_${name_index} = "${downstream_tool_addresses[$tools_index]}"
ADDITIONAL_TOOLS
done

# cat >>"$bootconfig_file" <<FOOTER
# FOOTER

echo "boot configuration: completed"
'''

var cvuv_cloud_init = replace(cvuv_cloud_init_template, 'DOWNSTREAM_CAPTURE_IPS', empty(cstorvCaptureIpAddress) ? downstreamTools : '${cstorvCaptureIpAddress},${downstreamTools}')

// Variables - end
//////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
// Resources - start

// TODO: is there a way to condition on null values instead of the magic 'new' string?
resource monitoringVnet 'Microsoft.Network/virtualNetworks@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: virtualNetwork.addressPrefixes
    }
  }
  // TODO: is this the correct key for the tag?
  tags: contains(tags, 'Microsoft.Network/virtualNetworks') ? tags['Microsoft.Network/virtualNetworks'] : null
}

resource captureSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  name: virtualNetwork.subnets.monitoringSubnet.name
  parent: monitoringVnet
  properties: {
    addressPrefix: virtualNetwork.subnets.monitoringSubnet.addressPrefix
    networkSecurityGroup: {
      id: captureSecurityGroup.id
    }
  }
}

var monitoringSubnetId = virtualNetwork.newOrExisting == 'new' ? captureSubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.monitoringSubnet.name)

resource managementSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  dependsOn: [
    captureSubnet
  ]
  name: virtualNetwork.subnets.managementSubnet.name
  parent: monitoringVnet
  properties: {
    addressPrefix: virtualNetwork.subnets.managementSubnet.addressPrefix
    networkSecurityGroup: {
      id: managementSecurityGroup.id
    }
  }
}

var managementSubnetId = virtualNetwork.newOrExisting == 'new' ? managementSubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.managementSubnet.name)

resource functionsSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = if (virtualNetwork.newOrExisting == 'new') {
  dependsOn: [
    managementSubnet
  ]
  name: virtualNetwork.subnets.functionsSubnet.name
  parent: monitoringVnet
  properties: {
    addressPrefix: virtualNetwork.subnets.functionsSubnet.addressPrefix
    delegations: [
      {
        name: 'Microsoft.Web.serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

var functionsSubnetId = virtualNetwork.newOrExisting == 'new' ? functionsSubnet.id : resourceId(virtualNetwork.resourceGroup, 'Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, virtualNetwork.subnets.functionsSubnet.name)

// docs: https://learn.microsoft.com/en-us/azure/templates/microsoft.network/loadbalancers?pivots=deployment-language-bicep
resource lb 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: lbName
  location: location
  tags: contains(tags, 'Microsoft.Network/loadBalancers') ? tags['Microsoft.Network/loadBalancers'] : null
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    backendAddressPools: [
      {
        name: lbBePoolName
      }
    ]
    frontendIPConfigurations: [
      {
        name: '${lbName}-frontend'
        properties: {
          subnet: {
            id: monitoringSubnetId
          }
        }
      }
    ]
    loadBalancingRules: [
      {
        name: '${lbName}-to-vmss'
        properties: {
          // This combination of ports and protocol seems to check the "high availability ports" checkbox in the portal.
          frontendPort: 0
          backendPort: 0
          protocol: 'All'

          // TODO: might want this -- more research needed
          // idleTimeoutInMinutes: lbIdleTimeoutInMinutes

          enableTcpReset: true

          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', lbName, '${lbName}-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
          probe: {
            id: lbProbeId
          }
        }
      }
    ]
    probes: [
      {
        name: lbProbeName
        properties: {
          protocol: 'Https'
          port: 443
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 2
        }
        // Alternatively, used for testing:
        // properties: {
        //   protocol: 'Tcp'
        //   port: 443
        //   intervalInSeconds: 5
        //   numberOfProbes: 2
        // }
      }
    ]
  }
}

resource cclearNIC 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: cclearvName
  location: location
  dependsOn: [
    monitoringVnet
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'management-ipcfg'
        properties: {
          subnet: {
            id: managementSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: managementSecurityGroup.id
    }
  }
  tags: contains(tags, 'Microsoft.Network/networkInterfaces') ? tags['Microsoft.Network/networkInterfaces'] : null
}

// docs: https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachines?pivots=deployment-language-bicep
resource cclearVm 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  dependsOn: [
    monitoringVnet
  ]
  name: cclearvName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: cclearvVmSize
    }
    storageProfile: {
      imageReference: {
        id: cclearvVmImageId
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      dataDisks: [
        {
          name: '${cclearvName}-DataDisk1'
          lun: 1
          createOption: 'Empty'
          diskSizeGB: 500
          caching: 'ReadWrite'
          deleteOption: 'Delete'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cclearNIC.id
        }
      ]
    }
    osProfile: {
      computerName: cclearvName
      adminUsername: adminUser
      adminPassword: sshPublicKey
      linuxConfiguration: linuxConfiguration
    }
  }
  tags: contains(tags, 'Microsoft.Compute/virtualMachines') ? union(tags['Microsoft.Compute/virtualMachines'], { 'cpacket:ApplianceType': 'cClear-V' }) : { 'cpacket:ApplianceType': 'cClear-V' }
}

resource cstorvCaptureNIC 'Microsoft.Network/networkInterfaces@2023-04-01' = if (cstorvEnable) {
  name: '${cstorvName}-cap-nic'
  location: location
  dependsOn: [
    monitoringVnet
  ]
  properties: {
    ipConfigurations: [
      {
        name: '${cstorvName}-cap-ipcfg'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: cstorvCaptureIpAddress
          subnet: {
            id: captureSubnet.id
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: captureSecurityGroup.id
    }
  }
  tags: contains(tags, 'Microsoft.Network/networkInterfaces') ? tags['Microsoft.Network/networkInterfaces'] : null
}

// There seems to be an issue when creating VMs that don't have public networking/ip configs setup 
// seems as though you have to create the nic and VM's separately see https://github.com/Azure/azure-rest-api-specs/issues/19446 
resource cstorvManagementNIC 'Microsoft.Network/networkInterfaces@2023-04-01' = if (cstorvEnable) {
  name: '${cstorvName}-mgmt-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: '${cstorvName}-mgmt-ipcfg'
        properties: {
          subnet: {
            id: managementSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: managementSecurityGroup.id
    }
  }
  tags: contains(tags, 'Microsoft.Network/networkInterfaces') ? tags['Microsoft.Network/networkInterfaces'] : null
}

resource cstorvm 'Microsoft.Compute/virtualMachines@2021-03-01' = if (cstorvEnable) {

  // There were errors about the vnet resource not found.
  // This could be because there are no references to the vnet resource here -- the monsubnetId is a variable
  dependsOn: [
    monitoringVnet
  ]

  name: cstorvName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: cstorvVmSize
    }
    storageProfile: {
      imageReference: {
        // This image is in a region, and if you deploy to another, an error will be thrown.
        id: cstorvVmImageId
      }
      osDisk: {
        osType: 'Linux'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      dataDisks: [for j in range(0, cstorvVmNumDisks): {
        name: '${cstorvName}-datadisk-${j}'
        lun: j
        createOption: 'Empty'
        diskSizeGB: cstorvVmDiskSize
        caching: 'ReadWrite'
        deleteOption: cstorvDataDiskDeleteOption
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cstorvManagementNIC.id
          properties: {
            primary: false
          }
        }
        {
          id: cstorvCaptureNIC.id
          properties: {
            primary: true
          }
        }

      ]
    }

    osProfile: {
      computerName: cstorvName
      adminUsername: adminUser
      adminPassword: sshPublicKey
      linuxConfiguration: linuxConfiguration
      //customData: loadFileAsBase64('./cstorv-cloud-init.sh')
    }
  }
  tags: contains(tags, 'Microsoft.Compute/virtualMachines') ? tags['Microsoft.Compute/virtualMachines'] : null
}

// https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachinescalesets?pivots=deployment-language-bicep#virtualmachinescalesetproperties
// example: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/quick-create-bicep-windows?tabs=CLI
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2022-11-01' = {

  // Encountered a case that seemed like a race condition: deployment failed indicating that the load balancer didn't exist.
  // ... so adding an explicit dependency here.
  // docs: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/resource-dependencies
  // ALSO NOTE: ran this many times __without__ adding this -- so its also hard to verify directly if this actually fixed it. 
  // ...that said, adding this did not throw any errors, and I verified that it is deploying with this dependsOn block added: you're welcome. 
  dependsOn: [
    monitoringVnet
    functionsSubnet
    lb
  ]

  name: '${vmssName}-${deploymentId}'
  location: location
  tags: contains(tags, 'Microsoft.Compute/virtualMachineScaleSets') ? tags['Microsoft.Compute/virtualMachineScaleSets'] : null

  sku: {
    name: vmssVmSize
    tier: 'Standard'
    capacity: vmssMin
  }

  properties: {
    orchestrationMode: 'Uniform'
    overprovision: false
    // https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachinescalesets?pivots=deployment-language-bicep#automaticrepairspolicy
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: vmssInstRepairGracePeriod
    }

    // https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachinescalesets?pivots=deployment-language-bicep#scaleinpolicy
    scaleInPolicy: {
      rules: [
        'Default'
      ]
    }

    upgradePolicy: {
      // TODO: we may want to change this to Rolling - and match the settings Jake is using in CLI
      mode: 'Manual'
      // automaticOSUpgradePolicy: {}
      // rollingUpgradePolicy: {}
    }

    virtualMachineProfile: {

      osProfile: {
        computerNamePrefix: '${deploymentId}-cvuv-'
        adminUsername: adminUser
        adminPassword: sshPublicKey
        linuxConfiguration: linuxConfiguration // TODO: workaround for https://github.com/Azure/bicep/issues/449

        customData: base64(cvuv_cloud_init)
      }

      storageProfile: {

        // imageReference docs: https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachinescalesets?pivots=deployment-language-bicep#imagereference
        // Generic test with ubuntu...
        // Get these field details from this command : az vm image list --output table --publisher Canonical --all
        // imageReference: {
        //   publisher: 'Canonical'
        //   offer: '0001-com-ubuntu-server-jammy'
        //   sku: '22_04-lts'
        //   version: 'latest'
        // }

        imageReference: {
          // If the image id is pointing to an image in another subscription, an error will be thrown if "image sharing" is not enabled.
          // If the image is in one region, and you deploy to another, an error will be thrown.
          id: cvuvVmImageId
        }

        osDisk: {
          createOption: 'FromImage'
          // Leaving as a placeholder in case we want to experiment with larger osDisks at this level
          // diskSizeGB: 80
          osType: 'Linux'
        }

        // Data disks not required by cvuv currently
        // dataDisks: {}
      }

      networkProfile: {
        healthProbe: {
          // Should be able to use the same health probe as the LB
          id: lbProbeId
        }

        networkInterfaceConfigurations: [
          {
            name: '${deploymentId}-cvuv-cap-nic'

            properties: {
              primary: true
              enableAcceleratedNetworking: true
              enableIPForwarding: true
              ipConfigurations: [
                {
                  name: '${deploymentId}-cap-ipcfg'
                  properties: {
                    subnet: {
                      id: monitoringSubnetId
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: lbPoolId
                      }
                    ]
                  }
                }
              ]
            }
          }
          {
            name: '${deploymentId}-cvuv-man-nic'

            properties: {
              primary: false
              enableAcceleratedNetworking: true
              enableIPForwarding: false
              ipConfigurations: [
                {
                  name: '${deploymentId}-man-ipcfg'
                  properties: {
                    subnet: {
                      id: managementSubnet.id
                    }
                    // loadBalancerBackendAddressPools: [
                    //   {
                    //     id: lbPoolId
                    //   }
                    // ]
                  }
                }
              ]
            }
          } ]

      }

    }

  }
}

// docs: https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/autoscalesettings?pivots=deployment-language-bicep
// example: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/quick-create-bicep-windows?tabs=CLI
// https://github.com/cPacketNetworks/ccloud-cli/blob/46f4e7134db8f3f206321873f0e4cf54cbb3fe09/azure/scale.set.lb.tf/main.tf#L391
// https://github.com/cPacketNetworks/ccloud-cli/blob/46f4e7134db8f3f206321873f0e4cf54cbb3fe09/azure/scale.set.lb.tf/variables.tf#L133
resource vmssautoscalesettings 'Microsoft.Insights/autoscalesettings@2021-05-01-preview' = {
  name: '${vmssName}-${deploymentId}'
  location: location
  // using the *same* tags we used for the scale sets above
  tags: contains(tags, 'Microsoft.Compute/virtualMachineScaleSets') ? tags['Microsoft.Compute/virtualMachineScaleSets'] : null

  properties: {
    // an error is thrown if this name is not the same as the resource name above ...weird.
    name: '${vmssName}-${deploymentId}'
    targetResourceUri: vmss.id
    enabled: true
    profiles: [
      {
        name: '${deploymentId}-net-scale-prof'
        capacity: {
          minimum: string(vmssMin)
          maximum: string(vmssMax)
          default: string(vmssMin)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Network in Total'
              metricResourceUri: vmss.id
              timeGrain: autoscaleUpTimeGrain
              statistic: 'Average'
              timeWindow: autoscaleUpTimeWindow
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: autoscaleUpThreshhold
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: autoscaleUpCooldown
            }
          }
          {
            metricTrigger: {
              metricName: 'Network in Total'
              metricResourceUri: vmss.id
              timeGrain: autoscaleDownTimeGrain
              statistic: 'Average'
              timeWindow: autoscaleDownTimeWindow
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: autoscaleDownThreshhold
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: autoscaleDownCooldown
            }
          }
        ]
      }
    ]
  }
}

resource managementSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'managementSecurityGroup'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'allow-https'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource captureSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'captureSecurityGroup'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-vxlan'
        properties: {
          priority: 100
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '4789'
        }
      }
    ]
  }
}

resource hostplan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'cpacketappliances'
  kind: 'elastic'
  location: location
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  }
}

resource cpacketappliancesStorage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  name: 'ccloud${deploymentId}'
  location: location
  tags: {}
  properties: {
    minimumTlsVersion: 'TLS1_0'
    allowBlobPublicAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource cpacketappliancesMonitoring 'Microsoft.Insights/components@2020-02-02' = {
  name: 'cpacketappliances'
  location: location
  tags: {}
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
    IngestionMode: 'ApplicationInsights'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource vmssevents 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  properties: {
    source: resourceGroup().id
    topicType: 'Microsoft.Resources.ResourceGroups'
  }
  identity: {
    type: 'None'
  }
  location: 'global'
  tags: {}
  name: 'vmss-events'
}
