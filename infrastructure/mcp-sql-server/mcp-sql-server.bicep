// Main infrastructure deployment for MSSQL MCP Server
// This template deploys:
// - Azure Key Vault with API key secret
// - Container Apps Environment with Log Analytics
// - User-Assigned Managed Identity
// - Container App with Key Vault reference

@description('The location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
param environmentName string = 'prod'

@description('Name prefix for all resources')
param resourcePrefix string = 'mssql-mcp'

@description('Container image to deploy (format: registry.azurecr.io/image:tag)')
param containerImage string

@description('Azure SQL Server name (without .database.windows.net)')
param sqlServerName string

@description('Azure SQL Database name')
param sqlDatabaseName string

@description('API key for MCP authentication (will be stored in Key Vault)')
@secure()
param mcpApiKey string

@description('Allowed CORS origins (comma-separated)')
param allowedOrigins string = 'https://ai.azure.com'

@description('Enable rate limiting')
param enableRateLimiting bool = true

@description('Container CPU cores')
param cpu string = '0.5'

@description('Container memory')
param memory string = '1Gi'

@description('Minimum replicas')
param minReplicas int = 1

@description('Maximum replicas')
param maxReplicas int = 3

@description('Current user object ID for Key Vault access (optional)')
param currentUserObjectId string = ''

// Generate unique names
var uniqueSuffix = uniqueString(resourceGroup().id)
var keyVaultName = 'kv${take(replace(resourcePrefix, '-', ''), 8)}${take(uniqueSuffix, 8)}'  // Max 24 chars
var containerAppName = '${resourcePrefix}-${environmentName}'
var managedEnvironmentName = '${resourcePrefix}-env-${uniqueSuffix}'
var managedIdentityName = '${resourcePrefix}-id-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-logs-${uniqueSuffix}'

// Extract ACR name from container image
var acrName = split(split(containerImage, '/')[0], '.')[0]

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// Azure Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Store MCP API Key in Key Vault
resource mcpApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mcp-api-key'
  properties: {
    value: mcpApiKey
    contentType: 'text/plain'
  }
}

// Grant managed identity Key Vault Secrets User role
resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'SecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant current user Key Vault Secrets User role (for agent deployment)
resource currentUserKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(currentUserObjectId)) {
  name: guid(keyVault.id, currentUserObjectId, 'CurrentUserSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Get reference to existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Grant managed identity AcrPull role on the registry
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Get reference to existing SQL Server (for reference only - not used for role assignment)
// Role assignment must be done manually or via SQL grants
// resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' existing = {
//   name: sqlServerName
//   scope: resourceGroup(sqlServerResourceGroup)
// }

// Note: SQL permissions are granted manually via SQL commands
// See docs/SELF_HOSTED_MCP.md for SQL grant instructions

// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: managedEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        corsPolicy: {
          allowedOrigins: split(allowedOrigins, ',')
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
          allowCredentials: true
        }
      }
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: managedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'mcp-api-key'
          keyVaultUrl: mcpApiKeySecret.properties.secretUri
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mssql-mcp-server'
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'AUTH_MODE'
              value: 'apikey'
            }
            {
              name: 'API_KEY'
              secretRef: 'mcp-api-key'
            }
            {
              name: 'SERVER_NAME'
              value: '${sqlServerName}${environment().suffixes.sqlServerHostname}'
            }
            {
              name: 'DATABASE_NAME'
              value: sqlDatabaseName
            }
            {
              name: 'SQL_AUTH_MODE'
              value: 'managed-identity'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'AZURE_CLIENT_ID_SQL'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'ALLOWED_ORIGINS'
              value: allowedOrigins
            }
            {
              name: 'ENABLE_RATE_LIMITING'
              value: string(enableRateLimiting)
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    acrPullRole
    keyVaultSecretsUser
  ]
}

// Outputs
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name
output keyVaultName string = keyVault.name
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityName string = managedIdentity.name
