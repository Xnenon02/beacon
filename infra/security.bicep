@description('Name of the Key Vault. 3-24 chars, must start with a letter.')
@minLength(3)
@maxLength(24)
param vaultName string

@description('Name of the existing web app that will read secrets.')
param appName string

@description('Your own objectId, so you can read the secret from the terminal.')
param deployerObjectId string

@description('Name of the secret in the vault.')
param secretName string = 'demo-secret'

@description('Secret value. Never put this in the parameter file.')
@secure()
param secretValue string

@description('Region. Defaults to the resource group location.')
param location string = resourceGroup().location

var secretsRead = [ 'get', 'list' ]
var secretsWrite = [ 'get', 'list', 'set' ]

resource app 'Microsoft.Web/sites@2025-03-01' existing = {
  name: appName
}

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.identity.principalId
        permissions: {
          secrets: secretsRead
        }
      }
      {
        tenantId: subscription().tenantId
        objectId: deployerObjectId
        permissions: {
          secrets: secretsWrite
        }
      }
    ]
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: vault
  name: secretName
  properties: {
    value: secretValue
  }
}

output vaultUri string = vault.properties.vaultUri
output secretUri string = secret.properties.secretUri
