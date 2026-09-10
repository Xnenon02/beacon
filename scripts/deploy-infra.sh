#!/usr/bin/env bash
# Deploys the infrastructure for the web app track (plan + web app).
# Run from the repo root.
# Usage: ./scripts/deploy-infra.sh [--what-if] <resource-group> [parameter-file]
# With --what-if the deployment is only previewed. No resources change; the
# resource group itself is still created if missing, because what-if needs it.

set -euo pipefail

# Read the optional flag first, then drop it, so the arguments below keep their
# positions whether or not it was given.
WHAT_IF=false
if [ "${1:-}" = "--what-if" ]; then
  WHAT_IF=true
  shift
fi

RESOURCE_GROUP="${1:?Provide the resource group as the first argument}"
PARAM_FILE="${2:-infra/main.bicepparam}"
LOCATION="${LOCATION:-westeurope}"
TEMPLATE="infra/main.bicep"

echo "Template:       $TEMPLATE"
echo "Parameters:     $PARAM_FILE"
echo "Resource group: $RESOURCE_GROUP"

# The resource group is torn down at the end of every lesson day, so it is usually
# missing when this script runs. Creating it here is what makes one command enough.
# Note: this happens with --what-if too, because what-if also needs the group to
# exist. An empty resource group costs nothing.
if [ "$(az group exists --name "$RESOURCE_GROUP")" = "false" ]; then
  echo "Group:          missing, creating it in $LOCATION"
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
else
  echo "Group:          already exists"
fi

if [ "$WHAT_IF" = true ]; then
  echo "Mode:           preview (no resources change)"
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE" \
    --parameters "$PARAM_FILE"
  exit 0
fi

DEPLOYMENT_NAME="webapp-$(date +%Y%m%d-%H%M%S)"
echo "Mode:           deploy ($DEPLOYMENT_NAME)"

APP_URL=$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAM_FILE" \
  --query properties.outputs.appUrl.value \
  --output tsv)

echo "Done. App URL: $APP_URL"
