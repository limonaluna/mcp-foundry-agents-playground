# Deploy MSSQL MCP Server to Azure Container Apps with Key Vault
# PowerShell Script for Windows

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Deploying MSSQL MCP Server to Azure" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Step 0: Load configuration from .env file
Write-Host ""
Write-Host "📝 Step 0: Loading configuration..." -ForegroundColor Cyan

# Get Foundry root directory
$FOUNDRY_ROOT = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Load .env file from Foundry root
$envFile = Join-Path $FOUNDRY_ROOT ".env"
if (-not (Test-Path $envFile)) {
    Write-Host "   ❌ .env file not found at: $envFile" -ForegroundColor Red
    Write-Host "   Please copy .env.example to .env and configure it" -ForegroundColor Yellow
    exit 1
}

# Parse .env file
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $envVars[$key] = $value
        }
    }
}

# Extract configuration values
$SQL_SERVER_NAME = if ($envVars['SERVER_NAME']) { 
    $envVars['SERVER_NAME'].Replace('.database.windows.net', '') 
} else { 
    Write-Host "   ❌ SERVER_NAME not found in .env" -ForegroundColor Red
    Write-Host "   Please set SERVER_NAME in your .env file" -ForegroundColor Yellow
    exit 1
}

$SQL_DATABASE_NAME = if ($envVars['DATABASE_NAME']) { 
    $envVars['DATABASE_NAME'] 
} else { 
    Write-Host "   ❌ DATABASE_NAME not found in .env" -ForegroundColor Red
    Write-Host "   Please set DATABASE_NAME in your .env file" -ForegroundColor Yellow
    exit 1
}

# Determine deployment mode: PROJECT_NAME (new) or explicit resource names (existing)
$PROJECT_NAME = $envVars['PROJECT_NAME']
$ENVIRONMENT_NAME = if ($envVars['NODE_ENV']) { $envVars['NODE_ENV'] } else { "dev" }

if ($PROJECT_NAME) {
    # SCENARIO 1: Start from Scratch - use PROJECT_NAME to generate resource names
    Write-Host "   Deployment Mode: Start from Scratch (using PROJECT_NAME)" -ForegroundColor Cyan
    Write-Host "   Project Name: $PROJECT_NAME" -ForegroundColor Gray
    
    # Validate PROJECT_NAME
    if ($PROJECT_NAME -notmatch '^[a-z0-9]{1,10}$') {
        Write-Host "   ❌ PROJECT_NAME must be lowercase alphanumeric, max 10 characters" -ForegroundColor Red
        Write-Host "   Current value: $PROJECT_NAME" -ForegroundColor Yellow
        exit 1
    }
    
    # Generate resource names from PROJECT_NAME
    # Resource group: <project>-<env>-rg
    $RESOURCE_GROUP = if ($envVars['RESOURCE_GROUP']) { 
        $envVars['RESOURCE_GROUP'] 
    } else { 
        "$PROJECT_NAME-$ENVIRONMENT_NAME-rg" 
    }
    
    # Container registry: <project>acr (unique suffix added by Azure)
    $ACR_NAME = "$PROJECT_NAME" + "acr"
    
    # Resource prefix for other resources: <project>-<env>-mcp
    $RESOURCE_PREFIX = "$PROJECT_NAME-$ENVIRONMENT_NAME-mcp"
    
} else {
    # SCENARIO 2: Bring Your Own - use explicit values or defaults
    Write-Host "   Deployment Mode: Bring Your Own Resources (explicit configuration)" -ForegroundColor Cyan
    
    $RESOURCE_GROUP = if ($envVars['RESOURCE_GROUP']) { $envVars['RESOURCE_GROUP'] } else { "mcp" }
    $ACR_NAME = "mcpfoundryacr"
    $RESOURCE_PREFIX = "mssql-mcp"
}

# Common optional configuration
$LOCATION = if ($envVars['AZURE_LOCATION']) { $envVars['AZURE_LOCATION'] } else { "swedencentral" }
$ALLOWED_ORIGINS = if ($envVars['ALLOWED_ORIGINS']) { $envVars['ALLOWED_ORIGINS'] } else { "https://ai.azure.com" }
$ENABLE_RATE_LIMITING = if ($envVars['ENABLE_RATE_LIMITING'] -eq 'false') { $false } else { $true }

# Container image configuration
$IMAGE_NAME = "mssql-mcp-server"
$IMAGE_TAG = "latest"
$CONTAINER_IMAGE = "$ACR_NAME.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

# Container configuration (defaults)
$CPU = "0.5"
$MEMORY = "1Gi"
$MIN_REPLICAS = 1
$MAX_REPLICAS = 3

Write-Host "   ✓ Configuration loaded from .env" -ForegroundColor Green
Write-Host "     Resource Group: $RESOURCE_GROUP" -ForegroundColor Gray
Write-Host "     Location: $LOCATION" -ForegroundColor Gray
Write-Host "     SQL Server: $SQL_SERVER_NAME" -ForegroundColor Gray
Write-Host "     Database: $SQL_DATABASE_NAME" -ForegroundColor Gray

# Step 1: Verify Azure login
Write-Host ""
Write-Host "📝 Step 1: Verifying Azure login..." -ForegroundColor Cyan
$currentAccount = az account show --query "{Subscription:name, User:user.name}" -o tsv 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "   ✓ Logged in as: $($currentAccount -split "`t" | Select-Object -Last 1)" -ForegroundColor Green
} else {
  Write-Host "   Please login first with: az login" -ForegroundColor Red
  exit 1
}

# Step 2: Create or use existing Resource Group
Write-Host ""
Write-Host "📝 Step 2: Ensuring resource group exists..." -ForegroundColor Cyan
az group create `
  --name $RESOURCE_GROUP `
  --location $LOCATION `
  --output none
Write-Host "   ✓ Using resource group: $RESOURCE_GROUP" -ForegroundColor Green

# Step 3: Create or use existing Azure Container Registry
Write-Host ""
Write-Host "📝 Step 3: Ensuring Azure Container Registry exists..." -ForegroundColor Cyan

# Check if ACR already exists
$existingAcr = az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query name -o tsv 2>$null
if ($existingAcr) {
  Write-Host "   ✓ Using existing ACR: $ACR_NAME" -ForegroundColor Green
} else {
  az acr create `
    --resource-group $RESOURCE_GROUP `
    --name $ACR_NAME `
    --sku Basic `
    --admin-enabled true `
    --output none
  Write-Host "   ✓ Created ACR: $ACR_NAME" -ForegroundColor Green
}

# Step 4: Build and push Docker image (unless skipped)
if (-not $SkipBuild) {
  Write-Host ""
  Write-Host "📝 Step 4: Building and pushing container image..." -ForegroundColor Cyan
  
  $APP_ROOT = Join-Path $FOUNDRY_ROOT "app"
  
  Write-Host "   Source: $APP_ROOT" -ForegroundColor Gray
  Write-Host "   Image: $CONTAINER_IMAGE" -ForegroundColor Gray
  
  az acr build `
    --registry $ACR_NAME `
    --image "${IMAGE_NAME}:${IMAGE_TAG}" `
    --file "$APP_ROOT/Dockerfile" `
    $APP_ROOT `
    --output table
    
  Write-Host "   ✓ Container image built and pushed" -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "⊘ Step 4: Skipping container build (using existing image)" -ForegroundColor Gray
}

# Step 5: Generate API key
Write-Host ""
Write-Host "📝 Step 5: Generating secure API key..." -ForegroundColor Cyan
$apiKeyBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($apiKeyBytes)
$API_KEY = [Convert]::ToBase64String($apiKeyBytes).Replace('+', '-').Replace('/', '_').Substring(0, 32)
Write-Host "   ✓ API key generated" -ForegroundColor Green

# Step 6: Deploy infrastructure with Bicep
Write-Host ""
Write-Host "📝 Step 6: Deploying infrastructure with Bicep..." -ForegroundColor Cyan
Write-Host "   Template: mcp-sql-server.bicep" -ForegroundColor Gray
Write-Host "   Parameters from: .env file" -ForegroundColor Gray
Write-Host "   Resources:" -ForegroundColor Gray
Write-Host "     • Azure Key Vault" -ForegroundColor Gray
Write-Host "     • Container Apps Environment" -ForegroundColor Gray
Write-Host "     • Managed Identity" -ForegroundColor Gray
Write-Host "     • Container App (MCP server)" -ForegroundColor Gray
Write-Host ""

# Get current user object ID for Key Vault access
Write-Host "   Getting current user object ID for Key Vault access..." -ForegroundColor Gray
$CURRENT_USER_ID = az ad signed-in-user show --query "id" -o tsv
Write-Host "   Current user ID: $CURRENT_USER_ID" -ForegroundColor Gray

$deployment = az deployment group create `
    --resource-group $RESOURCE_GROUP `
    --template-file "mcp-sql-server.bicep" `
    --parameters environmentName=$ENVIRONMENT_NAME `
    --parameters resourcePrefix=$RESOURCE_PREFIX `
    --parameters containerImage=$CONTAINER_IMAGE `
    --parameters sqlServerName=$SQL_SERVER_NAME `
    --parameters sqlDatabaseName=$SQL_DATABASE_NAME `
    --parameters mcpApiKey=$API_KEY `
    --parameters allowedOrigins=$ALLOWED_ORIGINS `
    --parameters enableRateLimiting=$ENABLE_RATE_LIMITING `
    --parameters cpu=$CPU `
    --parameters memory=$MEMORY `
    --parameters minReplicas=$MIN_REPLICAS `
    --parameters maxReplicas=$MAX_REPLICAS `
    --parameters currentUserObjectId=$CURRENT_USER_ID `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
  Write-Host "   ❌ Deployment failed!" -ForegroundColor Red
  exit 1
}

$CONTAINER_APP_URL = $deployment.properties.outputs.containerAppUrl.value
$CONTAINER_APP_NAME = $deployment.properties.outputs.containerAppName.value
$KEY_VAULT_NAME = $deployment.properties.outputs.keyVaultName.value
$MANAGED_IDENTITY_ID = $deployment.properties.outputs.managedIdentityClientId.value
$MANAGED_IDENTITY_NAME = $deployment.properties.outputs.managedIdentityName.value

Write-Host "   ✓ Infrastructure deployed successfully!" -ForegroundColor Green
Write-Host ""

# Step 6.5: Trigger new revision if image was built
if (-not $SkipBuild) {
  Write-Host "📝 Step 6.5: Triggering new revision with updated image..." -ForegroundColor Cyan
  Write-Host "   Container App: $CONTAINER_APP_NAME" -ForegroundColor Gray
  Write-Host "   Image: $CONTAINER_IMAGE" -ForegroundColor Gray
  
  az containerapp update `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --image $CONTAINER_IMAGE `
    --output none
  
  Write-Host "   ✓ New revision deployed" -ForegroundColor Green
  Write-Host ""
}

# Step 7: Display deployment summary
Write-Host "📋 Step 7: Deployment Summary" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Gray
Write-Host "Container App URL:    $CONTAINER_APP_URL" -ForegroundColor White
Write-Host "Container App Name:   $CONTAINER_APP_NAME" -ForegroundColor White
Write-Host "Key Vault Name:       $KEY_VAULT_NAME" -ForegroundColor White
Write-Host "Managed Identity ID:  $MANAGED_IDENTITY_ID" -ForegroundColor White
Write-Host "Managed Identity Name: $MANAGED_IDENTITY_NAME" -ForegroundColor White
Write-Host "MCP Endpoint:         $CONTAINER_APP_URL/mcp" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Gray
Write-Host ""

# Step 8: Save deployment outputs in standard format
Write-Host "💾 Step 8: Saving Deployment Outputs" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

$deploymentOutputs = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    resourceGroup = $RESOURCE_GROUP
    location = $LOCATION
    containerApp = @{
        name = $CONTAINER_APP_NAME
        url = $CONTAINER_APP_URL
        mcpEndpoint = "$CONTAINER_APP_URL/mcp"
    }
    keyVault = @{
        name = $KEY_VAULT_NAME
        url = "https://$KEY_VAULT_NAME.vault.azure.net"
    }
    managedIdentity = @{
        clientId = $MANAGED_IDENTITY_ID
        name = $MANAGED_IDENTITY_NAME
    }
    containerRegistry = @{
        name = $ACR_NAME
        loginServer = "$ACR_NAME.azurecr.io"
    }
}

# Save to config/mcp-sql-server-deployment-outputs.json in Foundry root
$ConfigDir = Join-Path $FOUNDRY_ROOT "config"

# Ensure config directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$outputFile = Join-Path $ConfigDir "mcp-sql-server-deployment-outputs.json"
$deploymentOutputs | ConvertTo-Json -Depth 10 | Out-File $outputFile -Encoding utf8
Write-Host "   ✓ Deployment outputs saved to: $outputFile" -ForegroundColor Green

# Also save deployment-info.json in config folder
$deploymentInfo = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    resourceGroup = $RESOURCE_GROUP
    containerAppUrl = $CONTAINER_APP_URL
    containerAppName = $CONTAINER_APP_NAME
    keyVaultName = $KEY_VAULT_NAME
    managedIdentityId = $MANAGED_IDENTITY_ID
    mcpEndpoint = "$CONTAINER_APP_URL/mcp"
}
$deploymentInfoFile = Join-Path $ConfigDir "deployment-info.json"
$deploymentInfo | ConvertTo-Json | Out-File $deploymentInfoFile -Encoding utf8

# Step 9: Set environment variables for current session
Write-Host ""
Write-Host "� Step 9: Setting environment variables..." -ForegroundColor Cyan

$env:MCP_ENDPOINT = "$CONTAINER_APP_URL/mcp"
$env:CONTAINER_APP_URL = $CONTAINER_APP_URL
$env:CONTAINER_APP_NAME = $CONTAINER_APP_NAME
$env:KEY_VAULT_NAME = $KEY_VAULT_NAME
$env:RESOURCE_GROUP = $RESOURCE_GROUP
$env:AZURE_LOCATION = $LOCATION

Write-Host "   ✓ Environment variables set for current session" -ForegroundColor Green
Write-Host "     MCP_ENDPOINT=$env:MCP_ENDPOINT" -ForegroundColor Gray
Write-Host "     KEY_VAULT_NAME=$env:KEY_VAULT_NAME" -ForegroundColor Gray

# Step 10: Update config.json if it exists (backward compatibility)
Write-Host ""
Write-Host "📝 Step 10: Updating config/config.json (if exists)..." -ForegroundColor Cyan

$configFile = Join-Path $ConfigDir "config.json"

if (Test-Path $configFile) {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    
    # Update MCP server URL in agents section
    if ($config.agents -and $config.agents.sql -and $config.agents.sql.mcpServer) {
        $config.agents.sql.mcpServer.url = "$CONTAINER_APP_URL/mcp"
    }
    
    # Update infrastructure section with deployment outputs
    if (-not $config.infrastructure) {
        $config.infrastructure = @{}
    }
    if (-not $config.infrastructure.mcp) {
        $config.infrastructure.mcp = @{}
    }
    
    # Update container app settings
    if (-not $config.infrastructure.mcp.containerApp) {
        $config.infrastructure.mcp.containerApp = @{}
    }
    $config.infrastructure.mcp.containerApp.name = $CONTAINER_APP_NAME
    $config.infrastructure.mcp.containerApp.url = $CONTAINER_APP_URL
    
    # Update Key Vault settings
    if (-not $config.infrastructure.mcp.keyVault) {
        $config.infrastructure.mcp.keyVault = @{}
    }
    $config.infrastructure.mcp.keyVault.name = $KEY_VAULT_NAME
    
    $config | ConvertTo-Json -Depth 100 | Set-Content $configFile -Encoding utf8
    Write-Host "   ✓ Updated config/config.json with deployment values" -ForegroundColor Green
} else {
    Write-Host "   ℹ config/config.json not found - using config/deployment-outputs.json instead" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Container App URL:" -ForegroundColor Cyan
Write-Host "   $CONTAINER_APP_URL" -ForegroundColor White
Write-Host ""
Write-Host "🔐 Security:" -ForegroundColor Cyan
Write-Host "   API Key stored in: Azure Key Vault ($KEY_VAULT_NAME)" -ForegroundColor White
Write-Host "   Secret Name: mcp-api-key" -ForegroundColor Gray
Write-Host ""
Write-Host "🔗 MCP Endpoint:" -ForegroundColor Cyan
Write-Host "   $CONTAINER_APP_URL/mcp" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test health endpoint:" -ForegroundColor White
Write-Host "     Invoke-RestMethod -Uri $CONTAINER_APP_URL/health" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Configure Azure AI Foundry agent:" -ForegroundColor White
Write-Host "     cd ..\agent" -ForegroundColor Gray
Write-Host "     python configure-agent.py" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Test the agent:" -ForegroundColor White
Write-Host "     python test-agent.py" -ForegroundColor Gray
Write-Host ""

