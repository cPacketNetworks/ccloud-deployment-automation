#!/usr/bin/env bash
set -e
set -x

resource_group="${RESOURCE_GROUP:?Missing RESOURCE_GROUP env var}"
# The function app and its single function will have the same name.
function_name="${FUNCTION_NAME:?Missing FUNCTION_NAME env var}"
event_grid_system_topic_name="${TOPIC_NAME:?Missing TOPIC_NAME env var}}"
event_grid_system_topic_subscription_name="${SUBSCRIPTION_NAME:?Missing SUBSCRIPTION_NAME env var}"

# The location of the Event Grid system topic must be global because of an Azure bug.
# location="eastus2"
# location="global"
 
# count=0
# while true; do
#   state="$(az functionapp show --name "$function_name" --resource-group "$resource_group" --query 'state' -o tsv)"
#   if [[ "$state" == "Running" ]]; then
#     echo "Function app '$function_name' is running..."
#     break
#   fi
#   echo "Waiting for function app '$function_name' to be running..."
#   sleep 10
#   count=$((count + 1))
#   if [[ $count -gt 10 ]]; then
#     echo "Timed out waiting for function app to be running."
#     exit 1
#   fi
# done

# Publish the function app code.
func azure functionapp publish "${function_name}" --python

# Create the Event Grid system topic.
# rg_id="$(az group show -g "$resource_group" --query 'id' -o tsv)"
# 
# # Before of Azure bug: https://stackoverflow.com/questions/70880703/creation-of-system-topic-failed-while-creating-event-subscription-in-azure-maps/70940961#70940961
# # --location should be specific to the resource group, but this fails with:
# #   System topic's location must match with location of the source resource <resource group id>
# az eventgrid system-topic create \
#   -g "$resource_group" \
#   --name "$event_grid_system_topic_name" \
#   --location "$location" \
#   --topic-type "Microsoft.Resources.ResourceGroups" \
#   --source "$rg_id" \
#   --identity systemassigned

function_id="$(az functionapp function list -g "$resource_group" -n "$function_name" --query '[0].id' --output tsv)"

az eventgrid system-topic event-subscription create \
  -n "$event_grid_system_topic_subscription_name" \
  -g "$resource_group" \
  --system-topic-name "$event_grid_system_topic_name" \
  --endpoint "$function_id" \
  --endpoint-type azurefunction
