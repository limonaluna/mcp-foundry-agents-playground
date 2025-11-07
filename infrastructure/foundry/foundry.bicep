// Azure AI Foundry Infrastructure Deployment
// This template deploys:
// - Azure AI Foundry Account (CognitiveServices/accounts)
// - Azure AI Foundry Project
// - GPT-4o-mini model deployment

@description('The location for all resources')
param location string = resourceGroup().location

@description('Name prefix for Azure AI Foundry resources')
param foundryPrefix string = 'mcp-foundry'

@description('Name for the AI Foundry project')
param projectName string = '${foundryPrefix}-project'

@description('Project description')
param projectDescription string = 'Azure AI Foundry project for MCP agent testing and development'

@description('Project display name')
param projectDisplayName string = 'MCP Foundry Project'

@description('Model to deploy (e.g., gpt-4o, gpt-4o-mini)')
param modelName string = 'gpt-4o-mini'

@description('Model format (OpenAI, etc.)')
param modelFormat string = 'OpenAI'

@description('Model version')
param modelVersion string = '2024-07-18'

@description('Model SKU name (GlobalStandard, Standard, etc.)')
param modelSkuName string = 'GlobalStandard'

@description('Model capacity (tokens per minute in thousands)')
param modelCapacity int = 150

// Generate unique names to avoid conflicts
var uniqueSuffix = uniqueString(resourceGroup().id)
var foundryName = toLower('${foundryPrefix}-${uniqueSuffix}')

/*
  Step 1: Create Azure AI Foundry Account
  This is a CognitiveServices/accounts resource with kind 'AIServices'
*/
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    // Required for AI Foundry - enables project management
    allowProjectManagement: true
    
    // Custom subdomain for API endpoints
    customSubDomainName: foundryName
    
    // Network configuration
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    
    // Support both Entra ID and API Key authentication
    disableLocalAuth: false
  }
}

/*
  Step 2: Deploy Model
  Deploy the specified model to the AI Foundry account
*/
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiFoundry
  name: modelName
  sku: {
    capacity: modelCapacity
    name: modelSkuName
  }
  properties: {
    model: {
      name: modelName
      format: modelFormat
      version: modelVersion
    }
  }
}

/*
  Step 3: Create AI Foundry Project
  Projects organize work and provide access management, data isolation, and cost tracking
*/
resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiFoundry
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
    displayName: projectDisplayName
  }
}

// Outputs for use in config files and other deployments
output foundryEndpoint string = aiFoundry.properties.endpoint
output foundryName string = aiFoundry.name
output foundryId string = aiFoundry.id
output projectName string = aiProject.name
output projectId string = aiProject.id
// Construct the project endpoint in the required format for the Agent Service SDK
// Format: https://{foundry-name}.services.ai.azure.com/api/projects/{project-name}
output projectEndpoint string = 'https://${aiFoundry.name}.services.ai.azure.com/api/projects/${aiProject.name}'
output modelDeploymentName string = modelDeployment.name
output location string = location
