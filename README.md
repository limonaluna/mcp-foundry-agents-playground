# MSSQL MCP Server for Azure AI Foundry Agent Service

HTTP-based MCP server for Azure SQL Database, designed for Azure AI Foundry Agent Service integration.

## 🚀 Quick Start

**New to this project?** See [GETTING_STARTED.md](GETTING_STARTED.md) for step-by-step deployment guides.

### Two Deployment Scenarios:

1. **[Start from Scratch](GETTING_STARTED.md#scenario-1-start-from-scratch)** - Provide project name + SQL database, everything else auto-deployed
2. **[Bring Your Own Resources](GETTING_STARTED.md#scenario-2-bring-your-own-resources)** - Use existing Azure resources

### TL;DR - Start from Scratch

**Prerequisites:** Azure SQL Database with Azure AD authentication

```bash
# 1. Configure (set PROJECT_NAME, SERVER_NAME, DATABASE_NAME)
cp .env.example .env
# Edit .env

# 2. Install dependencies
pip install -r requirements.txt

# 3. Deploy MCP Server
cd infrastructure/mcp-sql-server
.\deploy.ps1

# 4. Grant database access (manual SQL script - see GETTING_STARTED.md Step 4)
# Run SQL to grant permissions to managed identity

# 5. Deploy SQL Agent
cd ../agents
python mcp-sql-agent.py

# 6. Test
cd ../../test
python test-sql-agent.py
```

## Status: ✅ Ready for Deployment

The server implements MCP protocol over SSE transport with authentication, ready for Azure deployment.

## Features

- ✅ **MCP Protocol over SSE**: Full Model Context Protocol support via Server-Sent Events
- ✅ **Authentication**: API key middleware with multiple auth methods
- ✅ **Rate Limiting**: Optional request throttling per API key
- ✅ **Azure SQL Integration**: Entra ID authentication with automatic token refresh
- ✅ **Containerized**: Docker support for easy deployment
- ✅ **Health Checks**: Built-in health monitoring
- ✅ **CORS**: Configured for Azure AI Foundry

## Quick Start

### Python Setup (for agents and tests)

```bash
# Install Python dependencies (agents and test scripts)
pip install -r requirements.txt
```

### Local Development

1. **Install Node.js dependencies:**
   ```bash
   cd app
   npm install
   ```

2. **Configure environment:**
   ```bash
   # Copy example configuration to .env at the root
   cp .env.example .env
   # Edit .env with your database settings
   ```

3. **Build and run:**
   ```bash
   npm run build
   npm start
   ```

4. **Test the server:**
   ```bash
   curl http://localhost:3000/health
   ```

### Local Development with Docker

For local development and testing with Docker, see [local/README.md](local/README.md).

Quick start:
```bash
cd local
docker-compose up -d
```

## Endpoints

### Health & Info
- `GET /health` - Health check (always accessible)
- `GET /info` - Server information and available tools

### MCP Protocol
- `GET /sse` - Establish SSE connection for MCP communication
- `POST /sse` - Send MCP messages (requires session ID)

## Tools (via MCP)

### read_data
Execute SELECT queries on the database.

**Example:**
```json
{
  "name": "read_data",
  "arguments": {
    "query": "SELECT TOP 10 * FROM SalesLT.Customer"
  }
}
```

### list_table
List all tables, optionally filtered by schema.

**Example:**
```json
{
  "name": "list_table",
  "arguments": {
    "parameters": ["SalesLT"]
  }
}
```

### describe_table
Get schema information for a table.

**Example:**
```json
{
  "name": "describe_table",
  "arguments": {
    "tableName": "Customer"
  }
}
```

## Authentication

The server supports two authentication modes configured via `AUTH_MODE` environment variable:

### Mode 1: API Key Authentication (Development)

Simple shared secret authentication for development and testing.

**Setup:**
```bash
# In .env
AUTH_MODE=apikey
API_KEY=your-secret-api-key-here
```

**Usage:**

1. **API Key Header:**
```bash
curl -H "x-api-key: your-secret-key" http://localhost:3000/sse
```

2. **Bearer Token:**
```bash
curl -H "Authorization: Bearer your-secret-key" http://localhost:3000/sse
```

3. **Query Parameter (Testing Only):**
```bash
curl "http://localhost:3000/sse?apiKey=your-secret-key"
```

**Optional Rate Limiting:**
```bash
ENABLE_RATE_LIMITING=true
RATE_LIMIT_MAX=100
RATE_LIMIT_WINDOW_MS=60000
```

### Mode 2: OAuth 2.0 / Azure AD (Production)

Enterprise-grade JWT bearer token authentication with Azure Active Directory.

**Features:**
- ✅ **User Identity Tracking**: Every operation tracked by Azure AD user (OID)
- ✅ **Audit Trail**: All responses include `executedBy` with user name and email
- ✅ **Role-Based Access Control (RBAC)**: Support for Azure AD app roles
- ✅ **Scope Validation**: Fine-grained permission checking
- ✅ **Token Security**: JWT signature validation, expiration, issuer verification

**Setup:**
```bash
# In .env
AUTH_MODE=oauth
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_ID=<your-client-id>
AZURE_AUDIENCE=api://<your-client-id>  # Optional, defaults to api://{CLIENT_ID}
```

**Usage:**
```bash
# Get Azure AD token
TOKEN=$(az account get-access-token --resource api://<client-id> --query accessToken -o tsv)

# Call API with token
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/sse
```

**Complete Setup Guide:** See [docs/OAUTH_SETUP.md](./docs/OAUTH_SETUP.md) for:
- Azure AD App Registration step-by-step
- Scope and role configuration
- Testing OAuth flow
- Deployment examples
- Troubleshooting

**User Context in Responses:**

With OAuth enabled, all tool responses include user information:
```json
{
  "success": true,
  "message": "Retrieved 42 record(s)",
  "data": [...],
  "executedBy": "John Doe (john.doe@contoso.com)",
  "executedAt": "2025-01-15T10:30:00.000Z"
}
```

## Environment Variables

### Required
- `SERVER_NAME` - Azure SQL server name
- `DATABASE_NAME` - Database name

### Authentication
- `AUTH_MODE` - Authentication mode: `apikey` or `oauth` (default: `apikey`)

**For API Key Mode:**
- `API_KEY` - Shared secret for authentication
- `ENABLE_RATE_LIMITING` - Enable rate limiting (default: `false`)
- `RATE_LIMIT_MAX` - Max requests per window (default: `100`)
- `RATE_LIMIT_WINDOW_MS` - Rate limit window in ms (default: `60000`)

**For OAuth Mode:**
- `AZURE_TENANT_ID` - Azure AD tenant ID (required for oauth)
- `AZURE_CLIENT_ID` - Azure AD application (client) ID (required for oauth)
- `AZURE_AUDIENCE` - Expected audience in JWT (optional, defaults to `api://{CLIENT_ID}`)

### Server Configuration
- `PORT` - Server port (default: `3000`)
- `ALLOWED_ORIGINS` - CORS origins (comma-separated, default: `*`)
- `CONNECTION_TIMEOUT` - SQL connection timeout in seconds (default: `30`)
- `TRUST_SERVER_CERTIFICATE` - Accept self-signed certs (default: `false`)

## Architecture

```
┌─────────────────────┐
│  Azure AI Foundry   │
│    Agent Service    │
└──────────┬──────────┘
           │ MCP over HTTP/SSE
           ▼
┌─────────────────────┐
│   MCP Server        │
│  (This Project)     │
│                     │
│  - SSE Transport    │
│  - Tool Handlers    │
│  - SQL Connection   │
│  - Auth Middleware  │
└──────────┬──────────┘
           │ Entra ID Auth
           ▼
┌─────────────────────┐
│  Azure SQL Database │
│    (contoso)        │
└─────────────────────┘
```

## Deployment

### Azure Container Apps (MCP Server)

Deploy the MCP server to Azure with a single command:

```powershell
# 1. Configure .env file at the Foundry root
cp .env.example .env
# Edit .env with your SQL server and database name

# 2. Deploy to Azure
cd infrastructure/mcp-sql-server
.\deploy.ps1
```

**What it does:**
- ✅ Loads configuration from `.env` file
- ✅ Builds Docker image from `app/` folder
- ✅ Deploys to Azure Container Apps
- ✅ Sets up Key Vault with API key
- ✅ Configures managed identity for SQL access
- ✅ Saves deployment outputs to `config/`

**All parameters are managed through `.env`** - no separate parameters file needed!

See [`infrastructure/mcp-sql-server/README.md`](infrastructure/mcp-sql-server/README.md) for detailed deployment guide.

### Azure AI Foundry Integration (Agent Setup)

After deploying the MCP server, integrate it with Azure AI Foundry:

1. **Deploy Model**: Deploy Azure OpenAI model (e.g., GPT-4o)
2. **Create Agent**: Create agent with MCP tool configuration
3. **Test Integration**: Verify agent can use SQL tools

See `deploy/ai-foundry/README.md` for complete AI Foundry accelerator.

**Quick Start:**
```powershell
# Navigate to AI Foundry deployment folder
cd deploy/ai-foundry

# Deploy model
.\deploy-model.ps1 -ResourceGroup "mcp" -HubName "foundry-ilona" -ProjectName "mcp"

# Create agent with MCP tool
.\create-mcp-agent.ps1 `
  -ProjectEndpoint "https://foundry-ilona.services.ai.azure.com/api/projects/mcp" `
  -ModelDeploymentName "gpt-4o" `
  -McpServerUrl "https://your-mcp-server.azurecontainerapps.io/sse"

# Test the agent
.\test-agent.ps1 -Query "List all SQL servers"
```

**Documentation:**
- `deploy/ai-foundry/README.md` - Complete setup guide
- `deploy/ai-foundry/DEPLOYMENT_GUIDE.md` - Step-by-step deployment
- `deploy/ai-foundry/AGENT_USAGE.md` - Code examples

## Development

### Scripts
- `npm run build` - Compile TypeScript
- `npm start` - Run production server
- `npm run dev` - Run with auto-reload

### Testing
- `node dist/test-auth.ts` - Test authentication
- `node dist/test-mcp-client.ts` - Test MCP communication

## Comparison with Node Version

| Feature | Node (stdio) | Foundry (HTTP/SSE) |
|---------|-------------|---------------------|
| Transport | stdio | HTTP/SSE |
| Protocol | MCP | MCP |
| VS Code | ✅ | ❌ |
| Foundry Agent | ❌ | ✅ |
| Authentication | N/A | API Key |
| Rate Limiting | N/A | ✅ |
| Containerized | ❌ | ✅ |
| Port | N/A | 3000 |

## Security

- ✅ API key authentication
- ✅ Rate limiting
- ✅ CORS protection
- ✅ Non-root Docker user
- ✅ Entra ID for SQL access
- ✅ SELECT-only queries for read_data tool

## Next Steps

1. Deploy to Azure Container Apps
2. Integrate with Azure AI Foundry Agent
3. Add comprehensive logging
4. Add telemetry and monitoring

## Documentation

- `IMPLEMENTATION_PLAN.md` - Development roadmap
- `FOUNDRY_INTEGRATION.md` - Azure AI Foundry integration guide
- `../Node/README.md` - Original stdio version

## Support

- Both Node and Foundry versions are maintained
- The Node version remains unchanged and fully functional
- They can run simultaneously on the same machine
