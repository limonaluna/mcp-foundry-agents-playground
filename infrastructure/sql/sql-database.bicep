// SQL Server and Database deployment for MCP
// This is a simplified template focused on MCP server needs

@description('The location for all resources')
param location string = resourceGroup().location

@description('SQL Server name (without .database.windows.net)')
param sqlServerName string

@description('SQL Database name')
param sqlDatabaseName string = 'contoso'

@description('Azure AD admin login name')
param azureADAdminLogin string

@description('Azure AD admin object ID')
param azureADAdminObjectId string

@description('Tenant ID for Azure AD')
param tenantId string = subscription().tenantId

@description('SKU name (e.g., GP_S_Gen5 for serverless)')
param skuName string = 'GP_S_Gen5'

@description('SKU tier')
param skuTier string = 'GeneralPurpose'

@description('SKU capacity (vCores)')
param skuCapacity int = 2

@description('Minimum capacity for serverless')
param minCapacity string = '0.5'

@description('Auto-pause delay in minutes')
param autoPauseDelay int = 60

@description('Sample schema to use (AdventureWorksLT for sample data)')
param sampleName string = 'AdventureWorksLT'

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: 'CloudSA${take(azureADAdminObjectId, 8)}'
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: azureADAdminLogin
      sid: azureADAdminObjectId
      tenantId: tenantId
      azureADOnlyAuthentication: true
    }
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// Set Azure AD administrator explicitly
resource sqlServerAdmin 'Microsoft.Sql/servers/administrators@2024-05-01-preview' = {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: azureADAdminLogin
    sid: azureADAdminObjectId
    tenantId: tenantId
  }
}

// Azure AD Only Authentication - ensure it's enforced
resource azureADAuth 'Microsoft.Sql/servers/azureADOnlyAuthentications@2024-05-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

// Allow Azure services to access server
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2024-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: skuName
    tier: skuTier
    family: 'Gen5'
    capacity: skuCapacity
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368 // 32 GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    autoPauseDelay: autoPauseDelay
    requestedBackupStorageRedundancy: 'Local'
    minCapacity: json(minCapacity)
    isLedgerOn: false
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'BillOverUsage'
    availabilityZone: 'NoPreference'
    sampleName: sampleName // AdventureWorksLT sample schema
  }
}

// Short-term backup retention
resource backupShortTerm 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2024-05-01-preview' = {
  parent: sqlDatabase
  name: 'default'
  properties: {
    retentionDays: 7
    diffBackupIntervalInHours: 12
  }
}

// Transparent Data Encryption
resource tde 'Microsoft.Sql/servers/databases/transparentDataEncryption@2024-05-01-preview' = {
  parent: sqlDatabase
  name: 'Current'
  properties: {
    state: 'Enabled'
  }
}

// Outputs
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
output sqlServerId string = sqlServer.id
output sqlDatabaseId string = sqlDatabase.id
