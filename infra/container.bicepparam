using './container.bicep'

param registryName = 'acrclo25namnwe'
param environmentName = 'cae-clo25-namnwe'
param containerAppName = 'ca-clo25-namnwe'
param containerImage = 'acrclo25namnwe.azurecr.io/beacon:v1'
param minReplicas = 1
param maxReplicas = 5
