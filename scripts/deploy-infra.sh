#!/usr/bin/env bash
# Deploys the infrastructure for the web app track (plan + web app).
# Run from the repo root.
# Usage: ./scripts/deploy-infra.sh [--what-if] <resource-group> [parameter-file]
# With --what-if the deployment is only previewed. No resources change; the
# resource group itself is still created if missing, because what-if needs it.

set -euo pipefail

# Git Bash on Windows rewrites any argument that starts with a single "/" into a
# Windows path (/subscriptions/... becomes C:/Program Files/Git/subscriptions/...),
# which makes az fail with MissingSubscription. This switches that off. It has no
# effect on Linux, macOS or the GitHub runner.
export MSYS_NO_PATHCONV=1

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
SP_NAME="${SP_NAME:-gh-clo25-namn-we}"
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

# Start the deployment and wait for it as two separate steps. When az both starts
# and follows a deployment it sometimes loses track of it (DeploymentNotFound)
# although Azure goes on to create it. Starting with --no-wait still stops here
# if the start itself fails; waiting by name does not depend on that first poll.
az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAM_FILE" \
  --no-wait \
  --output none

az deployment group wait \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --created --interval 10 --timeout 1800

# Do not trust the exit code of wait alone: check the end state ourselves.
STATE=$(az deployment group show \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.provisioningState \
  --output tsv)
if [ "$STATE" != "Succeeded" ]; then
  echo "Deployment $DEPLOYMENT_NAME ended in state: $STATE" >&2
  exit 1
fi

APP_URL=$(az deployment group show \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.outputs.appUrl.value \
  --output tsv)

echo "Done. App URL: $APP_URL"

# The identity survives a teardown. Its role assignment does not: the assignment
# belongs to the resource group, and dies with it. Grant it again if it is gone.
#
# Look the identity up rather than keeping its id in the file. Run from a
# terminal this succeeds. Run by the pipeline it comes back empty, because the
# service principal may not read the directory - and the block is then skipped,
# which is right, since it may not hand out roles either.
if [ -z "${SP_OBJECT_ID:-}" ]; then
  SP_OBJECT_ID=$(az ad sp list \
    --display-name "$SP_NAME" \
    --query "[?displayName=='$SP_NAME'].id" \
    --output tsv 2>/dev/null || true)
fi

if [ -n "${SP_OBJECT_ID:-}" ]; then
  SCOPE="/subscriptions/$(az account show --query id --output tsv)"
  SCOPE="$SCOPE/resourceGroups/$RESOURCE_GROUP"
  EXISTING=$(az role assignment list \
    --assignee-object-id "$SP_OBJECT_ID" \
    --scope "$SCOPE" \
    --fill-principal-name false \
    --query "[0].id" \
    --output tsv)
  if [ -z "$EXISTING" ]; then
    echo "Role:           granting Contributor to the pipeline identity"
    az role assignment create \
      --assignee-object-id "$SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role Contributor \
      --scope "$SCOPE" \
      --output none
  else
    echo "Role:           pipeline identity already has Contributor"
  fi
fi
