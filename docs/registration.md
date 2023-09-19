# Creating and configuring appliance registration

## Create the Function App

Choose a unique, meaningful name for the Function App: it is globally unique in the Azure cloud.
The Function App has been tested with Python 3.10.

![Create a Function App](/static-assets/registration/create-function-app.png "Create a Function App")

Choose the Premium Functions plan as it enables connectivity from the function to the VNET that hosts the appliances.
Select the Linux Plan that was created as part of the Bicep deployment.

![Premium hosting plan](/static-assets/registration/host-plan-type.png "Premium hosting plan")

Select the storage account for the Function App.
It was created as part of the Bicep deployment.

![Storage account](/static-assets/registration/storage-account.png "Storage account")

Enable the Function App to reach the VNET that hosts the VMSS scale set.
Connect the Function App to the subnet called functions-subnet created previously with the Bicep flow.

![Networking](/static-assets/registration/function-app-networking.png "Networking")

Select the Applications Insights object that was created earlier with Bicep.

![Application Insights](/static-assets/registration/application-insights.png "Application Insights")

Ignore the Deployment section, add any required tags, and click Create to provision the Function App.

## Function App Configuration

Add a configuration setting for the appliance password.
This is passed as an environment variable to the function and must be named ‘APPLIANCE_HTTP_BASIC_AUTH_PASSWORD’.

![Appliance password](/static-assets/registration/appliance-password-config.png "Appliance Password")

Assign a managed identity to the Function App so that it’s authenticated to Azure.

![Managed Identity ](/static-assets/registration/managed-identity.png "Managed Identity")

Authorize the Function App by assigning a role to its managed identity. Restrict the scope to the Resource Group, use the Contributor role.

TODO:  This should be a more narrow role.

![Assign Role](/static-assets/registration/assign-role.png "Assign Role")

## Function App Code

Add the function code to the Function App.
Run the following command from the directory containing the hosts.json file, and the contents will be uploaded to the Azure Function App.

```bash
func azure functionapp publish cpacketappliancesdoc --python
# upload the contents of the current directory to the Function App named 'cpacketappliancesdoc'
```

Note that the func executable is available by default in the Azure cloud shell.
If deploying from another Linux environment, you will likely need to install the Azure Function core tools like:

```bash
npm install -g azure-functions-core-tools@4 --unsafe-perm true
```

The directory containing the function app is:

Obtaining the code can be achieved by doing a Git clone of the directory, or downloading the release source, unzipping, and changing to that directory.

For instance,

```bash
git clone https://github.com/cPacketNetworks/ccloud-deployment-automation
cd ccloud-deployment-automation/automations/azure/registerappliances
func azure functionapp publish cpacketappliancesdoc --python
```

The end result should be that the function (as opposed to the Function App) should be listed in the Function App’s overview page.
The function code does not need to be named the same as the Function App.
(There could be many functions in a Function App.)

![Function code uploaded](/static-assets/registration/upload-success.png "Function code uploaded")

## Event Subscription

After the Function App is created and configured, create an Event Grid System topic and a subscription within the topic to trigger the function when Event Grid events occur in the resource group.

![Event Grid system topic](/static-assets/registration/event-subscription.png "Event Grid system topic")

This allows the function to be triggered when cVu-V instances are added or removed from the VMSS.

![Event Grid subscription](/static-assets/registration/direct-events-to-function.png "Subscribe to events")
