#!/usr/bin/env bash
set -e
set -x

# Variables that must be changed

# shellcheck disable=SC2034
location="eastus2"
resource_group="mbright-bicep-test"
app_name="registerangryhippo"
storage_name="$app_name"
zip_file="function_app.zip"
#plan_name="$app_name"

# Avoid changing the code below

# Choose EP1 to get vnet integration
# plan_id="$(az functionapp plan create \
#   --name "$plan_name" \
#   --resource-group "$resource_group" \
#   --is-linux true \
#   --sku EP1 \
#   --query 'id' \
#   --output tsv)"
plan_id="$(az appservice plan list -g "$resource_group" -o tsv --query '[0].id')"

# Not sure if this is strictly required
# az storage account create \
#   --name "$storage_name" \
#   --location "$location" \
#   --resource-group "$resource_group" \
#   --sku Standard_LRS
# storage_account_id="$(az storage account list -g "$resource_group" -o tsv --query '[0].id')"

az functionapp create \
  --resource-group "$resource_group" \
  --runtime python \
  --runtime-version 3.10 \
  --functions-version 4 \
  --name "$app_name" \
  --os-type linux \
  --storage-account "$storage_name" \
  --plan "$plan_id"

# Assign system assigned managed identity to function app
az functionapp identity assign \
  --name "$app_name" \
  --resource-group "$resource_group"

assignee_object="$(az functionapp identity show \
  --name "$app_name" \
  --resource-group "$resource_group" \
  --query "principalId" \
  --output tsv)"

# Should be scoped to resource group with --scope
# Defaults to scope == resource group
az role assignment create \
  --role "Contributor" \
  --assignee-object-id "$assignee_object" \
  --resource-group "$resource_group"

# This was required to get it to work
az functionapp config appsettings set \
  --name "$app_name" \
  --resource-group "$resource_group" \
  --settings AzureWebJobsFeatureFlags=EnableWorkerIndexing

# az functionapp config appsettings set \
#   --name "$app_name" \
#   --resource-group "$resource_group" \
#   --settings "SCM_DO_BUILD_DURING_DEPLOYMENT=true"

# https://github.com/Azure-Samples/function-app-arm-templates/wiki/Best-Practices-Guide#zipdeploy-run-from-package-with-arm-template
# az functionapp config appsettings set \
#   --name "$app_name" \
#   --resource-group "$resource_group" \
#   --settings "WEBSITE_RUN_FROM_PACKAGE=0"

# az webapp config appsettings set --resource-group <group-name> --name <app-name> --settings WEBSITE_RUN_FROM_PACKAGE="1"

# publish function code
func azure functionapp publish "$app_name"

# zip -r function_app.zip function_app.py host.json requirements.txt

# az functionapp deployment source config-zip \
#   --resource-group "$resource_group" \
#   --name "$app_name" \
#   --src "$zip_file" \
#   --build-remote true
#
