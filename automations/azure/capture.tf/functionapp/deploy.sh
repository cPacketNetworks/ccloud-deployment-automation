#!/usr/bin/env bash
set -e
set -x

resource_group="${RESOURCE_GROUP:?Missing RESOURCE_GROUP env var}"
# The function app and its single function will have the same name.
function_name="${FUNCTION_NAME:?Missing FUNCTION_NAME env var}"
event_grid_system_topic_name="${EVENT_GRID_TOPIC_NAME:?Missing EVENT_GRID_TOPIC_NAME env var}"
event_grid_system_topic_subscription_name="scaling"

# The location of the Event Grid system topic must be global because of an Azure bug.
# location="eastus2"

# Publish the function app code.
# Wait until the Function app is ready...
count=0
while true;do
  if func azure functionapp publish "${function_name}" --python; then
    break
  fi
  echo "Waiting for function app '$function_name' to be publishable..."
  sleep 10
  count=$((count + 1))
  if [[ $count -gt 10 ]]; then
    echo "Timed out waiting for function app to be publishable."
    exit 1
  fi
done

# Wait for function code to appear.
count=0
while true; do
  set +e
  function_id="$(az functionapp function list -g "$resource_group" -n "$function_name" --query '[0].id' --output tsv)"
  set -e
  if [[ "$function_id" != "" ]]; then
    break
  fi
  sleep 10
  count=$((count + 1))
  if [[ $count -gt 10 ]]; then
    echo "Timed out waiting for function code to be available."
    exit 1
  fi
done

# Create the Event Grid system topic.
rg_id="$(az group show -g "$resource_group" --query 'id' -o tsv)"

# Before of Azure bug: https://stackoverflow.com/questions/70880703/creation-of-system-topic-failed-while-creating-event-subscription-in-azure-maps/70940961#70940961
# --location should be specific to the resource group, but this fails with:
#   System topic's location must match with location of the source resource <resource group id>
az eventgrid system-topic create \
  -g "$resource_group" \
  --name "$event_grid_system_topic_name" \
  --location global \
  --topic-type "Microsoft.Resources.ResourceGroups" \
  --source "$rg_id" \
  --identity systemassigned

az eventgrid system-topic event-subscription create \
  -n "$event_grid_system_topic_subscription_name" \
  -g "$resource_group" \
  --system-topic-name "$event_grid_system_topic_name" \
  --endpoint "$function_id" \
  --endpoint-type azurefunction
