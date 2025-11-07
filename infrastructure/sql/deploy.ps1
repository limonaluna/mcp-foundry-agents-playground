# Deploy SQL Server and Database for MCP
# PowerShell Script for Windows
# 
# This script can work in two modes:
# 1. PROJECT_NAME mode: Reads .env file from Foundry root and uses PROJECT_NAME for naming
# 2. Parameter mode: Uses explicit parameters (backward compatible)

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlServerName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlDatabaseName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipManagedIdentityGrant
)

$ErrorActionPreference = "Stop"

# Function to load .env file
function Load-EnvFile {
    param([string]$EnvFilePath)
    
    if (Test-Path $EnvFilePath) {
        Write-Host "   Loading configuration from: $EnvFilePath" -ForegroundColor Gray
        Get-Content $EnvFilePath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $parts = $line.Split('=', 2)
                if ($parts.Length -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    [System.Environment]::SetEnvironmentVariable($key, $value, [System.EnvironmentVariableTarget]::Process)
                }
            }
        }
    }
}

# Function to generate resource names from PROJECT_NAME
function Get-ResourceNames {
    param([string]$ProjectName, [string]$EnvName)
    
    # Generate 8-character random suffix for uniqueness
    $randomSuffix = -join ((97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    
    return @{
        ResourceGroup = "$ProjectName-$EnvName-rg"
        SqlServer = "$ProjectName-sql-$randomSuffix"
        SqlDatabase = "$ProjectName-db"
    }
}

Write-Host "🗄️  Deploying SQL Server and Database" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Step 0: Load configuration
Write-Host ""
Write-Host "📝 Step 0: Loading configuration..." -ForegroundColor Cyan

$FOUNDRY_ROOT = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ENV_FILE = Join-Path $FOUNDRY_ROOT ".env"

# Load .env file if it exists
Load-EnvFile -EnvFilePath $ENV_FILE

# Determine deployment mode and resource names
$PROJECT_NAME = [System.Environment]::GetEnvironmentVariable("PROJECT_NAME")
$ENV_NAME = [System.Environment]::GetEnvironmentVariable("NODE_ENV")
if (-not $ENV_NAME) { $ENV_NAME = "dev" }

if ($PROJECT_NAME) {
    # SCENARIO 1: Start from scratch - use PROJECT_NAME
    Write-Host "   ✓ Using PROJECT_NAME mode: $PROJECT_NAME" -ForegroundColor Green
    
    # Validate PROJECT_NAME
    if ($PROJECT_NAME -notmatch '^[a-z0-9]{1,10}$') {
        Write-Host "   ❌ PROJECT_NAME must be lowercase alphanumeric, max 10 chars" -ForegroundColor Red
        exit 1
    }
    
    $resourceNames = Get-ResourceNames -ProjectName $PROJECT_NAME -EnvName $ENV_NAME
    
    # Override parameters with generated names
    if (-not $ResourceGroup) { $ResourceGroup = $resourceNames.ResourceGroup }
    if (-not $SqlServerName) { $SqlServerName = $resourceNames.SqlServer }
    if (-not $SqlDatabaseName) { $SqlDatabaseName = $resourceNames.SqlDatabase }
    if (-not $Location) { $Location = [System.Environment]::GetEnvironmentVariable("AZURE_LOCATION") }
    if (-not $Location) { $Location = "swedencentral" }
    
    Write-Host "   Resource Group: $ResourceGroup" -ForegroundColor Gray
    Write-Host "   SQL Server: $SqlServerName" -ForegroundColor Gray
    Write-Host "   Database: $SqlDatabaseName" -ForegroundColor Gray
    Write-Host "   Location: $Location" -ForegroundColor Gray
    
} else {
    # SCENARIO 2: Bring your own - use explicit values or defaults
    Write-Host "   ✓ Using explicit parameter mode" -ForegroundColor Green
    
    if (-not $ResourceGroup) { $ResourceGroup = "mcp" }
    if (-not $Location) { $Location = "swedencentral" }
    if (-not $SqlServerName) { $SqlServerName = "mcp-sql-" + -join ((97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_}) }
    if (-not $SqlDatabaseName) { $SqlDatabaseName = "contoso" }
    
    Write-Host "   Resource Group: $ResourceGroup" -ForegroundColor Gray
    Write-Host "   SQL Server: $SqlServerName" -ForegroundColor Gray
    Write-Host "   Database: $SqlDatabaseName" -ForegroundColor Gray
    Write-Host "   Location: $Location" -ForegroundColor Gray
}

# Step 1: Verify Azure login
Write-Host ""
Write-Host "📝 Step 1: Verifying Azure login..." -ForegroundColor Cyan
$account = az account show --query "{Subscription:name, User:user.name, TenantId:tenantId}" -o json | ConvertFrom-Json
if ($LASTEXITCODE -eq 0) {
  Write-Host "   ✓ Logged in as: $($account.User)" -ForegroundColor Green
  Write-Host "   Subscription: $($account.Subscription)" -ForegroundColor Gray
  Write-Host "   Tenant ID: $($account.TenantId)" -ForegroundColor Gray
} else {
  Write-Host "   Please login first with: az login" -ForegroundColor Red
  exit 1
}

# Step 2: Get current user's Azure AD info
Write-Host ""
Write-Host "📝 Step 2: Getting Azure AD admin information..." -ForegroundColor Cyan
$userInfo = az ad signed-in-user show --query "{displayName:displayName, objectId:id}" -o json | ConvertFrom-Json
Write-Host "   Admin: $($userInfo.displayName)" -ForegroundColor Gray
Write-Host "   Object ID: $($userInfo.objectId)" -ForegroundColor Gray

# Step 3: Create or use existing Resource Group
Write-Host ""
Write-Host "📝 Step 3: Ensuring resource group exists..." -ForegroundColor Cyan
az group create `
  --name $ResourceGroup `
  --location $Location `
  --output none
Write-Host "   ✓ Using resource group: $ResourceGroup" -ForegroundColor Green

# Step 4: Deploy SQL Server and Database
Write-Host ""
Write-Host "📝 Step 4: Deploying SQL Server and Database..." -ForegroundColor Cyan
Write-Host "   Server: $SqlServerName" -ForegroundColor Gray
Write-Host "   Database: $SqlDatabaseName" -ForegroundColor Gray
Write-Host "   Location: $Location" -ForegroundColor Gray

$deployment = az deployment group create `
  --resource-group $ResourceGroup `
  --template-file "sql-database.bicep" `
  --parameters sqlServerName=$SqlServerName `
  --parameters sqlDatabaseName=$SqlDatabaseName `
  --parameters location=$Location `
  --parameters azureADAdminLogin=$userInfo.displayName `
  --parameters azureADAdminObjectId=$userInfo.objectId `
  --parameters tenantId=$account.TenantId `
  --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
  Write-Host "   ❌ Deployment failed!" -ForegroundColor Red
  exit 1
}

$sqlServerFqdn = $deployment.properties.outputs.sqlServerFqdn.value

Write-Host "   ✓ SQL Server deployed successfully!" -ForegroundColor Green
Write-Host "   FQDN: $sqlServerFqdn" -ForegroundColor Gray

# Step 5: Grant Managed Identity access (if exists)
if (-not $SkipManagedIdentityGrant) {
    Write-Host ""
    Write-Host "📝 Step 5: Checking for Managed Identity..." -ForegroundColor Cyan
    
    # Determine expected managed identity name based on deployment mode
    $expectedIdentityName = if ($PROJECT_NAME) { "$PROJECT_NAME-$ENV_NAME-mcp-id" } else { "mssql-mcp-id" }
    
    # Try to find the managed identity
    $identity = az identity show --name $expectedIdentityName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
    
    if (-not $identity) {
        # Try to find by pattern
        $identities = az identity list --resource-group $ResourceGroup --query "[?contains(name, 'mcp')].{name:name, principalId:principalId}" -o json | ConvertFrom-Json
        if ($identities -and $identities.Count -gt 0) {
            $identity = $identities[0]
        }
    }
    
    if ($identity) {
        Write-Host "   ✓ Found managed identity: $($identity.name)" -ForegroundColor Green
        
        # Create SQL script to grant access
        $sqlScript = @"
-- Connect to your SQL database and run this script to grant access to the MCP Managed Identity
-- You can use Azure Portal Query Editor, SSMS, or Azure Data Studio

CREATE USER [$($identity.name)] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [$($identity.name)];
ALTER ROLE db_datawriter ADD MEMBER [$($identity.name)];
ALTER ROLE db_ddladmin ADD MEMBER [$($identity.name)];
GO
"@
        
        # Save SQL script to file
        $sqlScriptFile = Join-Path $FOUNDRY_ROOT "grant-managed-identity-access.sql"
        $sqlScript | Out-File $sqlScriptFile -Encoding utf8
        
        Write-Host ""
        Write-Host "   ⚠️  MANUAL STEP REQUIRED" -ForegroundColor Yellow
        Write-Host "   ======================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   To grant database access, run this SQL script:" -ForegroundColor White
        Write-Host "   File: $sqlScriptFile" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   Using Azure Portal:" -ForegroundColor White
        Write-Host "   1. Go to: https://portal.azure.com" -ForegroundColor Gray
        Write-Host "   2. Find your database: $SqlDatabaseName" -ForegroundColor Gray
        Write-Host "   3. Click 'Query editor' in the left menu" -ForegroundColor Gray
        Write-Host "   4. Login with Azure AD authentication" -ForegroundColor Gray
        Write-Host "   5. Paste and execute the SQL script" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   SQL Script:" -ForegroundColor White
        Write-Host "   -----------" -ForegroundColor Gray
        Write-Host $sqlScript -ForegroundColor Cyan
        Write-Host "   -----------" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "   ⚠️  No MCP managed identity found yet" -ForegroundColor Yellow
        Write-Host "   Deploy the MCP server first, then run this script again" -ForegroundColor Yellow
        Write-Host "   or manually grant access after MCP deployment" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "⊘ Step 5: Skipping Managed Identity grant" -ForegroundColor Gray
}

# Step 6: Save deployment outputs and update .env
Write-Host ""
Write-Host "📝 Step 6: Saving deployment outputs..." -ForegroundColor Cyan

$deploymentOutputs = @{
    timestamp = Get-Date -Format "o"
    resourceGroup = $ResourceGroup
    location = $Location
    sqlServer = @{
        name = $SqlServerName
        fqdn = $sqlServerFqdn
    }
    sqlDatabase = @{
        name = $SqlDatabaseName
    }
}

# Save to Foundry root
$outputFile = Join-Path $FOUNDRY_ROOT "sql-deployment-outputs.json"
$deploymentOutputs | ConvertTo-Json -Depth 10 | Out-File $outputFile -Encoding utf8
Write-Host "   ✓ Outputs saved to: $outputFile" -ForegroundColor Green

# Update .env file with SERVER_NAME and DATABASE_NAME if they don't exist
if (Test-Path $ENV_FILE) {
    $envContent = Get-Content $ENV_FILE -Raw
    $updated = $false
    
    if ($envContent -notmatch 'SERVER_NAME\s*=') {
        $envContent += "`nSERVER_NAME=$SqlServerName"
        $updated = $true
    }
    
    if ($envContent -notmatch 'DATABASE_NAME\s*=') {
        $envContent += "`nDATABASE_NAME=$SqlDatabaseName"
        $updated = $true
    }
    
    if ($updated) {
        $envContent | Out-File $ENV_FILE -Encoding utf8 -NoNewline
        Write-Host "   ✓ Updated .env with SERVER_NAME and DATABASE_NAME" -ForegroundColor Green
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ SQL Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "🗄️  SQL Server:" -ForegroundColor Cyan
Write-Host "   Name: $SqlServerName" -ForegroundColor White
Write-Host "   FQDN: $sqlServerFqdn" -ForegroundColor White
Write-Host "   Database: $SqlDatabaseName" -ForegroundColor White
Write-Host ""
Write-Host "🔐 Authentication:" -ForegroundColor Cyan
Write-Host "   Azure AD Only: Enabled" -ForegroundColor White
Write-Host "   Admin: $($userInfo.displayName)" -ForegroundColor White
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Run the SQL grant script (see above) to give MCP access" -ForegroundColor White
Write-Host "   2. Deploy the MCP server:" -ForegroundColor White
Write-Host "      cd ..\mcp-sql-server" -ForegroundColor Gray
Write-Host "      .\deploy.ps1" -ForegroundColor Gray
Write-Host ""
