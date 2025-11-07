# Grant Managed Identity access to SQL Database
# Run this after deploying the MCP server

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "mcp",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlServerName = "mcp-ilona",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlDatabaseName = "contoso"
)

$ErrorActionPreference = "Stop"

Write-Host "🔐 Granting Managed Identity Access to SQL Database" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""

# Step 1: Get MCP managed identity from deployment outputs
Write-Host "📝 Step 1: Loading MCP deployment outputs..." -ForegroundColor Cyan

$FOUNDRY_ROOT = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$outputFile = Join-Path $FOUNDRY_ROOT "mcp-sql-server-deployment-outputs.json"

if (-not (Test-Path $outputFile)) {
    Write-Host "   ❌ Deployment outputs not found: $outputFile" -ForegroundColor Red
    Write-Host "   Please deploy the MCP server first:" -ForegroundColor Yellow
    Write-Host "   cd ../mcp-sql-server && .\deploy.ps1" -ForegroundColor Gray
    exit 1
}

$mcpOutputs = Get-Content $outputFile -Raw | ConvertFrom-Json
$managedIdentityClientId = $mcpOutputs.managedIdentity.clientId

Write-Host "   ✓ Managed Identity Client ID: $managedIdentityClientId" -ForegroundColor Green

# Step 2: Get managed identity details
Write-Host ""
Write-Host "📝 Step 2: Getting managed identity details..." -ForegroundColor Cyan

$identities = az identity list --resource-group $ResourceGroup `
    --query "[?properties.clientId=='$managedIdentityClientId'].{name:name, principalId:properties.principalId}" `
    -o json | ConvertFrom-Json

if ($identities.Count -eq 0) {
    Write-Host "   ❌ Managed identity not found with Client ID: $managedIdentityClientId" -ForegroundColor Red
    exit 1
}

$identity = $identities[0]
Write-Host "   ✓ Managed Identity Name: $($identity.name)" -ForegroundColor Green
Write-Host "   Principal ID: $($identity.principalId)" -ForegroundColor Gray

# Step 3: Get SQL Server details
Write-Host ""
Write-Host "📝 Step 3: Getting SQL Server details..." -ForegroundColor Cyan

$sqlServerFqdn = az sql server show `
    --name $SqlServerName `
    --resource-group $ResourceGroup `
    --query fullyQualifiedDomainName `
    -o tsv

Write-Host "   ✓ SQL Server FQDN: $sqlServerFqdn" -ForegroundColor Green

# Step 4: Generate and display SQL script
Write-Host ""
Write-Host "📝 Step 4: Generating SQL script..." -ForegroundColor Cyan

$sqlScript = @"
-- Grant Managed Identity access to database
-- Run this as an Azure AD admin user

USE [$SqlDatabaseName];
GO

-- Create user for managed identity
CREATE USER [$($identity.name)] FROM EXTERNAL PROVIDER;
GO

-- Grant database roles
ALTER ROLE db_datareader ADD MEMBER [$($identity.name)];
ALTER ROLE db_datawriter ADD MEMBER [$($identity.name)];
ALTER ROLE db_ddladmin ADD MEMBER [$($identity.name)];
GO

-- Verify permissions
SELECT 
    dp.name AS UserName,
    dp.type_desc AS UserType,
    r.name AS RoleName
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
LEFT JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
WHERE dp.name = '$($identity.name)'
ORDER BY dp.name, r.name;
GO
"@

Write-Host "   ✓ SQL script generated" -ForegroundColor Green

# Step 5: Save SQL script to file
$sqlScriptFile = Join-Path $PSScriptRoot "grant-managed-identity-access.sql"
$sqlScript | Out-File $sqlScriptFile -Encoding UTF8

Write-Host ""
Write-Host "📄 SQL script saved to: $sqlScriptFile" -ForegroundColor Cyan
Write-Host ""

# Step 6: Display instructions
Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host "MANUAL STEP REQUIRED" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "To grant the Managed Identity access to the SQL database:" -ForegroundColor White
Write-Host ""
Write-Host "Option 1: Using Azure Data Studio or SSMS" -ForegroundColor Cyan
Write-Host "  1. Connect to: $sqlServerFqdn" -ForegroundColor Gray
Write-Host "  2. Use Azure AD authentication" -ForegroundColor Gray
Write-Host "  3. Open and execute: $sqlScriptFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Option 2: Using Azure Cloud Shell" -ForegroundColor Cyan
Write-Host "  sqlcmd -S $sqlServerFqdn -d $SqlDatabaseName -G -i grant-managed-identity-access.sql" -ForegroundColor Gray
Write-Host ""
Write-Host "Option 3: Using VS Code with SQL extension" -ForegroundColor Cyan
Write-Host "  1. Install 'SQL Server (mssql)' extension" -ForegroundColor Gray
Write-Host "  2. Connect using Azure AD" -ForegroundColor Gray
Write-Host "  3. Execute the SQL script" -ForegroundColor Gray
Write-Host ""
Write-Host "After granting access:" -ForegroundColor Cyan
Write-Host "  1. Restart the MCP container app:" -ForegroundColor Gray
Write-Host "     az containerapp revision restart --name $($mcpOutputs.containerApp.name) --resource-group $ResourceGroup" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Test the MCP agent:" -ForegroundColor Gray
Write-Host "     cd ../../test" -ForegroundColor Gray
Write-Host "     python test-sql-agent.py" -ForegroundColor Gray
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "SQL Script Content:" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray
Write-Host $sqlScript -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""
