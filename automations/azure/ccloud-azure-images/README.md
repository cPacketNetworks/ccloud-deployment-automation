# Copy the appliances into your Azure subscription

Before deploying the cPacket cCloud appliances, they must be copied into your Azure subscription.
The `ccloud-azure-images` script in this directory will copy the images specified in a file into in your Azure subscription.
It will then create the appliance images.

1. Obtain the appliance URL file from cPacket (default name `ccloud-urls.txt`).
1. Open the Azure cloud shell.
1. Upload it to the Azure cloud shell.
1. Download the `ccloud-azure-images` script.
    1. Immediately pipe it through the shell, or
    1. Run it specifying the name of your resource group, the storage account, the file name containing the appliance URLs.

## Obtain the appliance URLs file

Contact cPacket Networks to obtain the appliance URLs file.
This file contains the Shared Access Signature (SAS) URLs of the appliances.
(Each line of the file is a URL for an appliance that contains a Shared Access Signature (SAS).)

### Open the Azure cloud shell

In the Azure portal, open the Azure cloud shell by clicking on the icon in the upper right corner of the Azure portal.

![Open the shell](/static-assets/open-shell.png "Open the Azure cloud shell")

### Upload the file containing the appliance URLs

Upload this `ccloud-urls.txt` file to the Azure cloud shell.
(The root directory of the cloud shell is expected, and it is the default upload location.)

![Upload file](/static-assets/upload-file-to-shell.png "Upload the 'ccloud-urls.txt' file to shell")

### Create the images

The `ccloud-azure-images` script will create the images in your Azure subscription using the URLs provided in `ccloud-urls.txt`.

If you are creating a new resource group with a default name, you can pipe the script directly through the shell as the following invocation:

```bash
curl -s -L https://raw.githubusercontent.com/cPacketNetworks/ccloud-deployment-automation/main/automations/azure/ccloud-azure-images/ccloud-azure-images | bash
```

This creates a new resource group with a name such as `cpacket-ccloud-abc123` in the `eastus2` region.

Instead, if you have an existing resource group or would like to create the resource group with a specific name, first download the script and then supply it with the name of your resource group.

Execute the script with the `-g` flag:

```bash
curl -L https://raw.githubusercontent.com/cPacketNetworks/ccloud-deployment-automation/main/automations/azure/ccloud-azure-images/ccloud-azure-images | bash -s -- -g resource-group-name
```

After executing the script, you should have new resources in your resource group corresponding to the cCloud appliances in the URL file above:

![New resources](/static-assets/new-resources.png "cCloud images")

To find out about the script's options,

Download the script:

```bash
curl -s -L -O https://raw.githubusercontent.com/cPacketNetworks/ccloud-deployment-automation/main/automations/azure/ccloud-azure-images/ccloud-azure-images
```

Make it executable:

```bash
chmod +x ccloud-azure-images
```

Run it with the `-h` option:

```bash
./ccloud-azure-images -h
```
