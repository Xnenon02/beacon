// Infrastructure for the container track: registry, Container Apps
// environment, and the container app. Two logical parts in one file - the
// registry has to exist (and hold an image) before the app can start. A
// natural next step would be one module per part.

@description('Region. Defaults to the location of the resource group. Shared by both parts below.')
param location string = resourceGroup().location

// ======== Registry ========

@description('Registry name. Lowercase letters and digits only, 5-50 characters.')
@minLength(5)
@maxLength(50)
param registryName string

@description('Registry pricing tier. Basic is plenty for this course.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param registrySku string = 'Basic'

// ======== Container App ========

// -- Naming --

@description('Name of the Container Apps environment.')
param environmentName string

@description('Name of the container app. Becomes part of the URL.')
param containerAppName string

// -- Image --

@description('Full image reference, for example myregistry.azurecr.io/beacon:v1.')
param containerImage string

@description('Port the app listens on inside the container. .NET 10: 8080.')
param targetPort int = 8080

// -- Scaling --

@description('Minimum replicas. 0 = scale to zero, at the cost of a cold start.')
@minValue(0)
@maxValue(5)
param minReplicas int = 1

@description('Maximum number of replicas the app may scale out to.')
@minValue(1)
@maxValue(10)
param maxReplicas int = 5

@description('Concurrent requests per replica before another one starts.')
param concurrentRequests int = 20

// -- Compute --

@description('CPU cores per replica. Only these pairs are valid: 0.25/0.5Gi, 0.5/1.0Gi, 0.75/1.5Gi, 1.0/2.0Gi.')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1.0'
])
param containerCpu string = '0.5'

@description('Memory per replica. Must be the pair of the CPU value above.')
@allowed([
  '0.5Gi'
  '1.0Gi'
  '1.5Gi'
  '2.0Gi'
])
param containerMemory string = '1.0Gi'

// ======== Container App ========

// Same for everyone in the class, so a variable rather than a parameter.
var registryPasswordSecretName = 'acr-password'

// Reads from `app` below - Bicep resolves this by dependency, not by the
// order things are written in the file.
var appFqdn = app.properties.configuration.ingress.fqdn

// ======== Registry ========

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: registryName
  location: location
  sku: {
    name: registrySku
  }
  properties: {
    // Turns on a username and password for the registry, so the container app
    // can pull the image. A deliberate trade-off, written up in TUTORIAL.md
    // under "Security design". The better way is a managed identity with the
    // AcrPull role - built and verified, then reverted, because the role
    // assignment is deleted with the resource group on every teardown.
    adminUserEnabled: true
  }
}

// ======== Container App ========

resource environment 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: environmentName
  location: location
  properties: {}
}

resource app 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      // -- Ingress --
      ingress: {
        external: true          // reachable from the internet
        targetPort: targetPort  // the port the app listens on in the container
        allowInsecure: false    // HTTP is redirected to HTTPS
        transport: 'auto'
      }
      // -- Registry credentials --
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: registryPasswordSecretName
        }
      ]
      secrets: [
        {
          name: registryPasswordSecretName
          value: acr.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      // -- Container --
      containers: [
        {
          name: 'app'
          image: containerImage
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
        }
      ]
      // -- Scaling rule --
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '${concurrentRequests}'
              }
            }
          }
        ]
      }
    }
  }
}

// ======== Registry ========

output loginServer string = acr.properties.loginServer

// ======== Container App ========

output appUrl string = 'https://${appFqdn}'
output healthUrl string = 'https://${appFqdn}/health'
