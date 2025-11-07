# Getting Started with MSSQL MCP Server

This guide helps you deploy the MSSQL MCP Server to Azure in two simple scenarios.

## 📋 Prerequisites

- **Azure CLI** installed and authenticated (`az login`)
- **Python 3.8+** (for agent deployment and testing)
- **Node.js 18+** (only for local development)
- **Azure SQL Database** with Azure AD authentication enabled (see setup instructions below)

### Setting up Azure SQL Database

You need an Azure SQL Database before deploying the MCP server. You can:

1. **Use an existing database** - If you already have one, just note the server name and database name
2. **Create a new database manually** via Azure Portal:
   - Go to [Azure Portal](https://portal.azure.com)
   - Create SQL Database → Choose serverless tier for cost savings
   - **Important**: Enable "Azure AD-only authentication" during setup
   - Optionally use AdventureWorksLT sample data for testing

**Note:** The MCP server uses Azure AD (Entra ID) authentication, so your SQL database must support it.

## 🚀 Choose Your Deployment Scenario

### Scenario 1: Start from Scratch (Recommended)

**Best for:** New users, quick setup, learning

Just provide:
1. A unique **project name** (e.g., `mycompany`, `demo`)
2. Your **SQL database** connection details

All Azure MCP resources will be created automatically with consistent naming based on your project name.

**One manual step:** Grant database access to the MCP Managed Identity (simple SQL script provided).

### Scenario 2: Bring Your Own Resources

**Best for:** Advanced users with existing Azure resources

Provide specific names/endpoints for:
- Existing Azure AI Foundry project
- Existing Container Apps
- Existing Key Vault
- Other Azure resources

---

## 📝 Scenario 1: Start from Scratch

### Step 1: Configure Environment

```bash
# Copy the example configuration
cp .env.example .env

# Edit .env and set these required values:
# PROJECT_NAME=myproject          # Your unique project identifier (lowercase, max 10 chars)
# AZURE_LOCATION=swedencentral    # Azure region
# SERVER_NAME=your-server.database.windows.net  # Your existing SQL server
# DATABASE_NAME=your-database     # Your existing SQL database
```

**Example `.env` for starting from scratch:**

```bash
# Scenario 1: Start from scratch configuration

PROJECT_NAME=contoso
AZURE_LOCATION=swedencentral
NODE_ENV=dev

# Your existing SQL database
SERVER_NAME=mcp-sql.database.windows.net
DATABASE_NAME=adventureworks

# Optional: Customize if needed (defaults are fine)
ALLOWED_ORIGINS=https://ai.azure.com
ENABLE_RATE_LIMITING=true
```

### Step 2: Install Python Dependencies

```bash
pip install -r requirements.txt
```

### Step 3: Deploy MCP Server to Azure

### Step 3: Deploy MCP Server to Azure

```bash
cd infrastructure/mcp-sql-server
.\deploy.ps1
```

**What gets deployed:**

All resources are created with names based on your `PROJECT_NAME`:

| Resource | Naming Pattern | Example (PROJECT_NAME=contoso) |
|----------|---------------|--------------------------------|
| Resource Group | `<project>-<env>-rg` | `contoso-dev-rg` |
| Container Registry | `<project>acr<random>` | `contosoacr7xlf5mx5` |
| Container App | `<project>-<env>-mcp` | `contoso-dev-mcp` |
| Key Vault | `kv<project><random>` | `kvcontoso7xlf5mx5` |
| Managed Identity | `<project>-<env>-mcp-id` | `contoso-dev-mcp-id` |
| Log Analytics | `<project>-<env>-logs` | `contoso-dev-logs` |

✅ **After deployment completes:**
- MCP Server is running at a unique URL
- API key is stored in Key Vault
- All details saved to `mcp-sql-server-deployment-outputs.json`
- `.env` file is updated with deployment details

### Step 4: Grant SQL Database Access (Manual Step)

The MCP Server uses a Managed Identity to connect to your SQL database. You need to grant it permissions:

```sql
-- Connect to your SQL database using Azure Portal Query Editor, SSMS, or Azure Data Studio
-- Replace 'contoso-dev-mcp-id' with your actual managed identity name from Step 3

CREATE USER [contoso-dev-mcp-id] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [contoso-dev-mcp-id];
ALTER ROLE db_datawriter ADD MEMBER [contoso-dev-mcp-id];
ALTER ROLE db_ddladmin ADD MEMBER [contoso-dev-mcp-id];
```

**How to run this:**
1. Go to Azure Portal → Your SQL Database → Query editor
2. Login with Azure AD authentication
3. Paste and execute the SQL above
4. Find your managed identity name in the deployment output from Step 3

### Step 5: Deploy SQL Agent to Azure AI Foundry

**(Optional) Deploy Azure AI Foundry first if you don't have one:**

```bash
cd infrastructure/foundry
.\deploy.ps1
```

This creates Azure AI Foundry Hub, Project, and OpenAI model deployment.

**Deploy the SQL Agent:**

```bash
# Return to Foundry root
cd ..\..

cd infrastructure/agents
python mcp-sql-agent.py
```

This creates an Azure AI agent configured to use your MCP server.

### Step 6: Test the Agent

```bash
# Return to Foundry root
cd ..\..

cd test
python test-sql-agent.py
```

✅ **Done!** Your SQL MCP agent is ready to use.

---

## 🏢 Scenario 2: Bring Your Own Resources

### When to Use This

- You already have an Azure AI Foundry project
- You want to use existing Container Apps or Key Vaults
- You need specific resource names for compliance/governance

### Configuration

Edit `.env` and set the specific resource names/endpoints:

```bash
# Scenario 2: Bring your own resources

# Your existing SQL database
SERVER_NAME=your-server.database.windows.net
DATABASE_NAME=your-database

# Your existing Azure AI Foundry
AZURE_AI_ENDPOINT=https://my-project.services.ai.azure.com/api/projects/my-project
AZURE_AI_PROJECT_NAME=my-project
MODEL_DEPLOYMENT=gpt-4o

# Your existing Container App (if redeploying)
RESOURCE_GROUP=my-existing-rg
CONTAINER_APP_NAME=my-existing-app
KEY_VAULT_NAME=my-existing-vault

# Optional customization
AZURE_LOCATION=eastus
NODE_ENV=prod
```

### Deployment

Same deployment commands as Scenario 1, but the scripts will:
- Use your existing Foundry project (no new one created)
- Deploy to your specified resource group
- Reuse existing resources where specified

---

## 📁 Configuration Files Reference

### `.env` (at Foundry root)

**Required for Scenario 1:**
- `PROJECT_NAME` - Your unique project identifier
- `SERVER_NAME` - Your SQL server name
- `DATABASE_NAME` - Your SQL database name
- `AZURE_LOCATION` - Azure region (default: swedencentral)

**Required for Scenario 2:**
- `SERVER_NAME` & `DATABASE_NAME` - Your SQL database
- `AZURE_AI_ENDPOINT` - Your Foundry endpoint
- `AZURE_AI_PROJECT_NAME` - Your Foundry project name
- `MODEL_DEPLOYMENT` - Your model deployment name
- Other specific resource names as needed

### Auto-Generated Files

After deployment, these files contain resource details:

- `config/mcp-sql-server-deployment-outputs.json` - MCP server details
- `config/foundry-deployment-outputs.json` - Foundry project details
- `config/deployment-info.json` - Legacy format (backward compatibility)

---

## 🔍 Resource Naming Conventions

### Scenario 1 (Start from Scratch)

All resources follow this pattern: `<PROJECT_NAME>-<suffix>`

**Random Suffix:** Generated using Azure's `uniqueString()` function based on resource group ID (e.g., `7xlf5mx5`)

**Environment:** Included in name (e.g., `-dev-`, `-prod-`)

### Scenario 2 (Bring Your Own)

You control all resource names explicitly via `.env` variables.

---

## 🎯 Quick Start Checklist

**Scenario 1: Start from Scratch**
- [ ] Copy `.env.example` to `.env`
- [ ] Set `PROJECT_NAME` (unique, lowercase, max 10 chars)
- [ ] Set `SERVER_NAME` and `DATABASE_NAME` (your existing SQL DB)
- [ ] Set `AZURE_LOCATION` (optional, default: swedencentral)
- [ ] Run `pip install -r requirements.txt`
- [ ] Run `infrastructure/mcp-sql-server/deploy.ps1`
- [ ] Grant SQL database access to managed identity
- [ ] Run `infrastructure/agents/mcp-sql-agent.py`
- [ ] Test with `test/test-sql-agent.py`

**Scenario 2: Bring Your Own**
- [ ] Copy `.env.example` to `.env`
- [ ] Set all required Azure resource names/endpoints
- [ ] Set `SERVER_NAME` and `DATABASE_NAME`
- [ ] Run `pip install -r requirements.txt`
- [ ] Run deployment scripts as needed
- [ ] Test with `test/test-sql-agent.py`

---

## 💡 Tips

1. **Project Name:** Choose something memorable and unique to your organization
2. **Environment:** Use `dev` for development, `prod` for production (affects resource names)
3. **Region:** Choose a region close to your SQL database for best performance
4. **Costs:** Starting from scratch creates ~$50-100/month in Azure resources (depends on usage)

## 🆘 Troubleshooting

### "PROJECT_NAME not found in .env"
- Make sure you set `PROJECT_NAME` in your `.env` file
- The value must be lowercase, alphanumeric, max 10 characters

### "Azure AI Foundry endpoint not found"
- **Scenario 1:** Run `infrastructure/foundry/deploy.ps1` first
- **Scenario 2:** Set `AZURE_AI_ENDPOINT` in `.env` to your existing project

### "SQL connection failed"
- Ensure you granted the Managed Identity access to your database
- Check that `SERVER_NAME` and `DATABASE_NAME` are correct
- Verify your SQL server firewall allows Azure services

---

## 📚 Next Steps

- [Infrastructure Deployment Details](infrastructure/mcp-sql-server/README.md)
- [Agent Configuration Guide](infrastructure/agents/README.md)
- [Local Development Guide](local/README.md)
- [Main README](README.md)
