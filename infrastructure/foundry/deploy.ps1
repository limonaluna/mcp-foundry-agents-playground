#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Deploys Azure AI Foundry infrastructure for MCP agent development.

.DESCRIPTION
    This script deploys:
    - Azure AI Foundry Account (CognitiveServices/accounts)
    - Azure AI Foundry Project  
    - GPT model deployment (default: gpt-4o-mini)
    
    The deployment is separate from the MCP server infrastructure to allow
    testing agents without deploying the full MCP server stack.

.PARAMETER ResourceGroup
    The name of the resource group. Default: 'mcp'

.PARAMETER Location
    The Azure region. Default: 'swedencentral'

.PARAMETER FoundryPrefix
    Name prefix for Foundry resources. Default: 'mcp-foundry'

.PARAMETER ModelName
    Model to deploy. Default: 'gpt-4o-mini'

.PARAMETER ModelVersion
    Model version. Default: '2024-07-18'

.PARAMETER ModelCapacity
    Model capacity in thousands of tokens per minute. Default: 150

.EXAMPLE
    .\deploy-foundry.ps1
    
.EXAMPLE
    .\deploy-foundry.ps1 -ResourceGroup "my-rg" -Location "eastus" -ModelName "gpt-4o"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ResourceGroup,
    
    [Parameter()]
    [string]$Location,
    
    [Parameter()]
    [string]$FoundryPrefix,
    
    [Parameter()]
    [string]$ModelName,
    
    [Parameter()]
    [string]$ModelVersion,
    
    [Parameter()]
    [int]$ModelCapacity
)

$ErrorActionPreference = "Stop"

# Script directory
$ScriptDir = $PSScriptRoot
$BicepFile = Join-Path $ScriptDir "foundry.bicep"
$FoundryRoot = Split-Path (Split-Path $ScriptDir -Parent) -Parent  # Go up two levels: foundry -> infrastructure -> Foundry
$ConfigDir = Join-Path $FoundryRoot "config"
$ConfigFile = Join-Path $ConfigDir "config.json"

# Load .env file from Foundry root
$envFile = Join-Path $FoundryRoot ".env"
$envVars = @{}
if (Test-Path $envFile) {
    Write-Host "Loading configuration from .env file..." -ForegroundColor Gray
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $envVars[$key] = $value
                # Set environment variable for this session
                [System.Environment]::SetEnvironmentVariable($key, $value, [System.EnvironmentVariableTarget]::Process)
            }
        }
    }
    Write-Host "✓ Configuration loaded from .env" -ForegroundColor Green
} else {
    Write-Host "No .env file found at: $envFile" -ForegroundColor Yellow
}

# Load configuration if it exists
$config = $null
if (Test-Path $ConfigFile) {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

# Apply defaults with priority: Script param > Env var > Config file > PROJECT_NAME logic > Hardcoded default
if (-not $ResourceGroup) {
    # Check for PROJECT_NAME-based resource group (Scenario 1: Start from Scratch)
    $PROJECT_NAME = $env:PROJECT_NAME
    $ENVIRONMENT_NAME = if ($env:NODE_ENV) { $env:NODE_ENV } else { "dev" }
    
    if ($PROJECT_NAME) {
        $ResourceGroup = "$PROJECT_NAME-$ENVIRONMENT_NAME-rg"
        Write-Host "Using PROJECT_NAME-based resource group: $ResourceGroup" -ForegroundColor Yellow
    } else {
        # Scenario 2: Bring Your Own Resources or legacy behavior
        $ResourceGroup = if ($env:RESOURCE_GROUP) { $env:RESOURCE_GROUP }
                         elseif ($config -and $config.infrastructure.resourceGroup) { $config.infrastructure.resourceGroup }
                         else { "mcp" }
    }
}

if (-not $Location) {
    $Location = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION }
                elseif ($config -and $config.infrastructure.location) { $config.infrastructure.location }
                else { "swedencentral" }
}

if (-not $FoundryPrefix) {
    # Use PROJECT_NAME-based prefix if available
    if ($PROJECT_NAME) {
        $FoundryPrefix = "$PROJECT_NAME-foundry"
    } else {
        $FoundryPrefix = if ($env:FOUNDRY_PREFIX) { $env:FOUNDRY_PREFIX }
                         elseif ($config -and $config.infrastructure.foundry.prefix) { $config.infrastructure.foundry.prefix }
                         else { "mcp-foundry" }
    }
}

if (-not $ModelName) {
    $ModelName = if ($env:FOUNDRY_MODEL_NAME) { $env:FOUNDRY_MODEL_NAME }
                 elseif ($config -and $config.infrastructure.foundry.modelName) { $config.infrastructure.foundry.modelName }
                 else { "gpt-4o-mini" }
}

if (-not $ModelVersion) {
    $ModelVersion = if ($env:FOUNDRY_MODEL_VERSION) { $env:FOUNDRY_MODEL_VERSION }
                    elseif ($config -and $config.infrastructure.foundry.modelVersion) { $config.infrastructure.foundry.modelVersion }
                    else { "2024-07-18" }
}

if (-not $ModelCapacity -or $ModelCapacity -eq 0) {
    $ModelCapacity = if ($env:FOUNDRY_MODEL_CAPACITY) { [int]$env:FOUNDRY_MODEL_CAPACITY }
                     elseif ($config -and $config.infrastructure.foundry.modelCapacity) { [int]$config.infrastructure.foundry.modelCapacity }
                     else { 150 }
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "AZURE AI FOUNDRY INFRASTRUCTURE DEPLOYMENT" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# Validate prerequisites
Write-Host "Step 1: Validating Prerequisites" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Azure CLI not found. Please install from: https://aka.ms/azure-cli" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Azure CLI found" -ForegroundColor Green

# Check Azure CLI login
Write-Host "Checking Azure CLI authentication..." -ForegroundColor Gray
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "❌ Not logged in to Azure. Please run 'az login'" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "  Subscription: $($account.name)" -ForegroundColor Gray
Write-Host ""

# Validate Bicep file exists
if (-not (Test-Path $BicepFile)) {
    Write-Host "❌ Bicep file not found: $BicepFile" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Bicep template found" -ForegroundColor Green
Write-Host ""

# Step 2: Create resource group if it doesn't exist
Write-Host "Step 2: Resource Group Setup" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "Creating resource group '$ResourceGroup' in $Location..." -ForegroundColor Gray
    az group create --name $ResourceGroup --location $Location --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create resource group" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Resource group created" -ForegroundColor Green
} else {
    Write-Host "✓ Resource group '$ResourceGroup' exists" -ForegroundColor Green
}
Write-Host ""

# Step 3: Display deployment parameters
Write-Host "Step 3: Deployment Configuration" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray
Write-Host "Resource Group:   $ResourceGroup" -ForegroundColor White
Write-Host "Location:         $Location" -ForegroundColor White
Write-Host "Foundry Prefix:   $FoundryPrefix" -ForegroundColor White
Write-Host "Model:            $ModelName" -ForegroundColor White
Write-Host "Model Version:    $ModelVersion" -ForegroundColor White
Write-Host "Model Capacity:   $ModelCapacity K TPM" -ForegroundColor White
Write-Host ""

# Step 4: Deploy Bicep template
Write-Host "Step 4: Deploying Azure AI Foundry Infrastructure" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray
Write-Host "This will deploy:" -ForegroundColor Gray
Write-Host "  • Azure AI Foundry Account" -ForegroundColor Gray
Write-Host "  • Azure AI Foundry Project" -ForegroundColor Gray
Write-Host "  • $ModelName model deployment" -ForegroundColor Gray
Write-Host ""

$deploymentName = "foundry-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Starting deployment..." -ForegroundColor Gray

$deploymentResult = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --template-file $BicepFile `
    --parameters `
        location=$Location `
        foundryPrefix=$FoundryPrefix `
        modelName=$ModelName `
        modelVersion=$ModelVersion `
        modelCapacity=$ModelCapacity `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Deployment completed successfully" -ForegroundColor Green
Write-Host ""

# Step 5: Extract outputs
Write-Host "Step 5: Extracting Deployment Outputs" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

$outputs = ($deploymentResult | ConvertFrom-Json).properties.outputs

$foundryEndpoint = $outputs.foundryEndpoint.value
$foundryName = $outputs.foundryName.value
$projectName = $outputs.projectName.value
$projectEndpoint = $outputs.projectEndpoint.value
$modelDeploymentName = $outputs.modelDeploymentName.value
$deployedLocation = $outputs.location.value

Write-Host "✓ Outputs extracted" -ForegroundColor Green
Write-Host ""

# Step 6: Display deployment results
Write-Host "Step 6: Deployment Summary" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Gray
Write-Host "Foundry Endpoint:     $foundryEndpoint" -ForegroundColor White
Write-Host "Foundry Name:         $foundryName" -ForegroundColor White
Write-Host "Project Name:         $projectName" -ForegroundColor White
Write-Host "Project Endpoint:     $projectEndpoint" -ForegroundColor White
Write-Host "Model Deployment:     $modelDeploymentName" -ForegroundColor White
Write-Host "Location:             $deployedLocation" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Gray
Write-Host ""

# Step 7: Save deployment outputs to JSON file
Write-Host "Step 7: Saving Deployment Outputs" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

# Ensure config directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$outputsFile = Join-Path $ConfigDir "foundry-deployment-outputs.json"

$deploymentOutputs = @{
    timestamp = Get-Date -Format "o"
    resourceGroup = $ResourceGroup
    location = $deployedLocation
    foundry = @{
        name = $foundryName
        endpoint = $foundryEndpoint
    }
    project = @{
        name = $projectName
        endpoint = $projectEndpoint
    }
    model = @{
        name = $modelDeploymentName
        version = $ModelVersion
        capacity = $ModelCapacity
    }
}

$deploymentOutputs | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputsFile -Encoding UTF8

Write-Host "✓ Outputs saved to: $outputsFile" -ForegroundColor Green
Write-Host ""

# Step 8: Set environment variables for current session
Write-Host "Step 8: Setting Environment Variables" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

$env:AZURE_AI_ENDPOINT = $projectEndpoint
$env:AZURE_AI_PROJECT_NAME = $projectName
$env:MODEL_DEPLOYMENT = $modelDeploymentName
$env:AZURE_LOCATION = $deployedLocation
$env:RESOURCE_GROUP = $ResourceGroup

Write-Host "✓ Environment variables set for current session:" -ForegroundColor Green
Write-Host "  AZURE_AI_ENDPOINT       = $projectEndpoint" -ForegroundColor Gray
Write-Host "  AZURE_AI_PROJECT_NAME   = $projectName" -ForegroundColor Gray
Write-Host "  MODEL_DEPLOYMENT        = $modelDeploymentName" -ForegroundColor Gray
Write-Host "  AZURE_LOCATION          = $deployedLocation" -ForegroundColor Gray
Write-Host "  RESOURCE_GROUP          = $ResourceGroup" -ForegroundColor Gray
Write-Host ""

# Step 9: Update config.json if it exists
Write-Host "Step 9: Updating Configuration Files" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

$configFile = Join-Path $ConfigDir "config.json"

if (Test-Path $configFile) {
    Write-Host "Updating config/config.json..." -ForegroundColor Gray
    
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    
    # Update project settings
    $config.project.endpoint = $projectEndpoint
    $config.project.name = $projectName
    $config.project.location = $deployedLocation
    $config.project.modelDeployment = $modelDeploymentName
    
    $config | ConvertTo-Json -Depth 100 | Out-File -FilePath $configFile -Encoding UTF8
    
    Write-Host "✓ config/config.json updated" -ForegroundColor Green
} else {
    Write-Host "ℹ config/config.json not found (this is OK if you're using templates)" -ForegroundColor Yellow
}

Write-Host ""

# Step 10: Next steps
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. View your resources in Azure Portal:" -ForegroundColor White
Write-Host "   https://portal.azure.com/#@/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroup" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Access AI Foundry portal:" -ForegroundColor White
Write-Host "   https://ai.azure.com/" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Deploy an agent (requires MCP server):" -ForegroundColor White
Write-Host "   cd ../agent" -ForegroundColor Gray
Write-Host "   python mcp-sql-agent.py" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Test the agent:" -ForegroundColor White
Write-Host "   cd ../test" -ForegroundColor Gray
Write-Host "   python test-sql-agent.py" -ForegroundColor Gray
Write-Host ""
Write-Host "Configuration files updated:" -ForegroundColor Yellow
Write-Host "  • config/foundry-deployment-outputs.json" -ForegroundColor Gray
Write-Host "  • config/config.json (if exists)" -ForegroundColor Gray
Write-Host ""
Write-Host "Environment variables set for this session." -ForegroundColor Yellow
Write-Host "For permanent settings, add them to your .env file." -ForegroundColor Gray
Write-Host ""
