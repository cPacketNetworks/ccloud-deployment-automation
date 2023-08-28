#!/usr/bin/env bash
set -e
set -x

resource_group="mbright-bicep-test"
location="eastus2"

# The following file can be created by running creadUIDefinition.json in the Create UI Definition Sandbox
# in the Azure Portal.
#
# Here : https://portal.azure.com/?feature.customPortal=false#view/Microsoft_Azure_CreateUIDef/SandboxBlade
#
# Once you run through the UI steps in the sandbox, at the very end there is a small link at the
# bottom of the screen named "View outputs as payload" that will allow you to view the complete json.
# That json can be cut/paste into the parameters file: $parameters - which is referenced by this script.
parameters="parameters.json"

template="main.bicep"
compiled_template="main.json"

# generate a deployment name based on date/time - this is useful for debugging
deployment="deploy-$(date +%m%d%Y-%H-%M-%S)"

if [[ "$(az group exists --name "$resource_group")" == "false" ]]; then
  az group create --name "$resource_group" -l "$location"
fi

# this is a mostly useful way to do a dry run - informative output
# echo "running az deployment group what-if now..."
# az deployment group what-if \
#   --name "$deployment" \
#   --resource-group "$resource_group" \
#   --template-file "$template" \
#   --parameters "$parameters" \
#   --verbose --debug
# echo "exiting after what-if"
# exit 0

if az deployment group validate \
  --resource-group "$resource_group" \
  --template-file "$template" \
  --parameters "$parameters"; then
  :
else
  echo "Bicep validation failed"
  exit 1
fi

az bicep build --file "$template"

# https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-cli
echo "running az deployment group create now..."
az deployment group create \
  --name "$deployment" \
  --resource-group "$resource_group" \
  --template-file "$compiled_template" \
  --parameters "$parameters" \
  --verbose \
  --debug
