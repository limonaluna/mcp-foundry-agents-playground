# MCP SQL Server - Azure Deployment

Deploys the MSSQL MCP server to Azure Container Apps with Key Vault integration.

## Prerequisites

1. **Azure CLI** installed and authenticated (`az login`)
2. **Configuration file** - Copy `.env.example` to `.env` at Foundry root and configure:
   ```bash
   # From Foundry root directory:
   cp .env.example .env
   
   # Required settings in .env:
   SERVER_NAME=your-server.database.windows.net
   DATABASE_NAME=your-database
   
   # Optional (defaults shown):
   RESOURCE_GROUP=mcp
   AZURE_LOCATION=swedencentral
   ALLOWED_ORIGINS=https://ai.azure.com
   ENABLE_RATE_LIMITING=true
   ```

## Deployment

Run the deployment script from this directory:

```powershell
.\deploy.ps1
```

### Options

- **Skip Docker build** (use existing image):
  ```powershell
  .\deploy.ps1 -SkipBuild
  ```

## What Gets Deployed

The script automatically:

1. ✅ Loads configuration from `../../.env` file
2. ✅ Creates Azure Container Registry (if needed)
3. ✅ Builds and pushes Docker image from `../../app/`
4. ✅ Generates secure API key
5. ✅ Deploys infrastructure via Bicep:
   - Azure Key Vault (stores API key)
   - Container Apps Environment
   - User-Assigned Managed Identity
   - Container App (MCP server)
6. ✅ Grants SQL database access to managed identity
7. ✅ Saves deployment outputs to `../../config/mcp-sql-server-deployment-outputs.json`

## Configuration Source

All deployment parameters come from the **`.env` file** in the Foundry root:

| Parameter | .env Variable | Default | Description |
|-----------|---------------|---------|-------------|
| Resource Group | `RESOURCE_GROUP` | `mcp` | Azure resource group |
| Location | `AZURE_LOCATION` | `swedencentral` | Azure region |
| SQL Server | `SERVER_NAME` | *(required)* | SQL server name (without .database.windows.net) |
| Database | `DATABASE_NAME` | *(required)* | SQL database name |
| CORS Origins | `ALLOWED_ORIGINS` | `https://ai.azure.com` | Comma-separated origins |
| Rate Limiting | `ENABLE_RATE_LIMITING` | `true` | Enable rate limiting |
| Environment | `NODE_ENV` | `prod` | Environment name |

**No separate parameters.json file needed** - everything is managed through `.env`!

## Deployment Outputs

After deployment, find the outputs in:

- **`config/mcp-sql-server-deployment-outputs.json`** - Full deployment details
- **`config/deployment-info.json`** - Legacy format (backward compatibility)
- **`config/config.json`** - Updated with deployment URLs (if exists)

Key outputs:
- `containerAppUrl` - Base URL of the container app
- `mcpEndpoint` - Full MCP endpoint URL (add `/mcp`)
- `keyVaultName` - Key Vault name (contains API key)
- `managedIdentityClientId` - Identity for SQL access

## Next Steps

1. **Grant SQL Database Access** (if needed):
   ```sql
   -- Connect to your SQL database and run:
   CREATE USER [<managed-identity-name>] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [<managed-identity-name>];
   ALTER ROLE db_datawriter ADD MEMBER [<managed-identity-name>];
   ```

2. **Test the deployment**:
   ```powershell
   $url = (Get-Content config/mcp-sql-server-deployment-outputs.json | ConvertFrom-Json).containerApp.url
   Invoke-RestMethod -Uri "$url/health"
   ```

3. **Deploy agents**:
   ```powershell
   cd ../agents
   python mcp-sql-agent.py
   ```

## Troubleshooting

### Missing .env file
```
❌ .env file not found
```
**Solution**: Copy `.env.example` to `.env` at Foundry root and configure required values.

### SQL Server/Database not found
```
❌ SERVER_NAME not found in .env
```
**Solution**: Add `SERVER_NAME` and `DATABASE_NAME` to your `.env` file.

### Deployment fails
**Check**:
1. Azure CLI is logged in: `az account show`
2. Subscription is set: `az account set --subscription <name>`
3. Resource group exists or script has permissions to create it
4. Container image builds successfully (check Docker logs)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Azure Container Apps                                │
│  ┌──────────────────────────────────────────────┐  │
│  │ MCP Server Container                          │  │
│  │  • Node.js + TypeScript                       │  │
│  │  • Connects to SQL with Managed Identity      │  │
│  │  • API Key auth from Key Vault                │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
         │                           │
         │ Managed Identity          │ Key Vault Reference
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│ Azure SQL        │        │ Azure Key Vault  │
│  • Database      │        │  • API Key       │
└──────────────────┘        └──────────────────┘
```

## Files

- **`deploy.ps1`** - Main deployment script (reads from .env)
- **`mcp-sql-server.bicep`** - Infrastructure as code
- **`grant-managed-identity-access.sql`** - SQL permissions script
