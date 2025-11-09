# Self-Hosted MCP Server Guide

Deploy your own MCP server with custom tools to give Azure AI Foundry agents access to your data and business logic.

## 🎯 What You'll Build

A complete **SQL Agent** powered by your own MCP server that provides secure, authenticated access to Azure SQL Database.

- **Custom Tools**: `list_table`, `describe_table`, `read_data`
- **Enterprise Security**: Azure AD authentication, managed identity
- **Full Control**: Custom business logic, data access policies
- **⚠️ SDK Access Only**: Due to API authentication, works via SDK but not Azure AI Foundry playground

## 🏗️ Architecture

```
┌─────────────────────┐
│  Azure AI Foundry   │
│     SQL Agent       │
└──────────┬──────────┘
           │ MCP Protocol + API Key
           ▼
┌─────────────────────┐    ┌─────────────────────┐
│   Your MCP Server   │    │    Key Vault        │
│   (Container App)   │◄───┤   (API Keys)        │
│                     │    └─────────────────────┘
│  • Custom SQL Tools │
│  • Rate Limiting    │    ┌─────────────────────┐
│  • Audit Logging   │    │  Managed Identity   │
│  • Business Logic  │◄───┤  (SQL Auth)         │
└──────────┬──────────┘    └─────────────────────┘
           │ Azure AD Authentication
           ▼
┌─────────────────────┐
│  Azure SQL Database │
│     (Your Data)     │
└─────────────────────┘
```

## 📋 Prerequisites

- Azure subscription with sufficient permissions
- Azure SQL Database with Azure AD authentication enabled
- PowerShell 7+ (for deployment scripts)
- Docker (for local development)

## 🚀 Deployment Guide

### Two Deployment Scenarios

Choose the approach that fits your situation:

#### **🟢 Scenario 1: Start from Scratch**
Perfect for new projects or dedicated environments.

- Provide PROJECT_NAME + existing SQL database
- All MCP resources auto-created with consistent naming
- Clean resource group organization

#### **🔵 Scenario 2: Bring Your Own Resources**  
Ideal when you have existing Azure resources.

- Use existing Azure AI Foundry, Container Apps, Key Vault
- Integrate MCP server into current infrastructure
- Maximum flexibility and control

---

## 🏁 Scenario 1: Start from Scratch

**📖 This guide covers both scenarios in detail below**

### Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env: Set PROJECT_NAME=myproject, SERVER_NAME, DATABASE_NAME

# 2. Install dependencies  
pip install -r requirements.txt

# 3. Deploy MCP Server
cd infrastructure/mcp-sql-server
.\deploy.ps1

# 4. Grant database access (manual SQL script)
# Run provided SQL commands to grant managed identity permissions

# 5. Deploy Azure AI Foundry
cd ../foundry
.\deploy.ps1

# 6. Deploy SQL Agent
cd ../agents  
python mcp-sql-agent.py

# 7. Test end-to-end
cd ../../test
python test-sql-agent.py

## ⚠️ Important Limitation

**SDK-Only Access**: Due to API key authentication requirements, self-hosted MCP agents currently only work via SDK/programmatic access. Testing in the Azure AI Foundry playground portal does not support API key authentication for MCP servers.

**Workarounds:**
- Use the provided Python test scripts for validation
- Build custom applications using the Azure AI SDK
- Consider external MCP services for playground testing
```

**What Gets Created:**
```
myproject-dev-rg/
├── myproject-dev-mcp-dev (Container App)
├── myprojectacr (Container Registry)  
├── kvmyproject****** (Key Vault)
├── myproject-foundry-****** (AI Foundry Hub)
└── myproject-foundry-project (AI Foundry Project)
```

---

## 🔧 Scenario 2: Bring Your Own Resources

**📖 Full walkthrough provided below**

### Configuration

```bash
# In .env - specify all your existing resources
RESOURCE_GROUP=my-existing-rg
ACR_NAME=mycontainerregistry
CONTAINER_APP_NAME=my-mcp-server
KEY_VAULT_NAME=my-keyvault

AZURE_AI_ENDPOINT=https://my-foundry.services.ai.azure.com/api/projects/my-project
AZURE_AI_PROJECT_NAME=my-project
```

### Deploy to Existing Infrastructure

```bash
# Deploy MCP server to your existing resources
cd infrastructure/mcp-sql-server
.\deploy.ps1

# Deploy agent to your existing Foundry
cd ../agents
python mcp-sql-agent.py
```

---

## 🛠️ MCP Server Features

### Custom SQL Tools

#### `list_table`
List all tables, optionally filtered by schema.

```json
{
  "name": "list_table", 
  "arguments": {
    "parameters": ["SalesLT"]  // Optional schema filter
  }
}
```

#### `describe_table`  
Get detailed schema information for a table.

```json
{
  "name": "describe_table",
  "arguments": {
    "tableName": "SalesLT.Customer"
  }
}
```

#### `read_data`
Execute SELECT queries with results.

```json
{
  "name": "read_data",
  "arguments": {
    "query": "SELECT TOP 10 * FROM SalesLT.Customer WHERE City = 'Seattle'"
  }
}
```

### Security Features

#### **🔐 Authentication**
- **API Key**: Secure key stored in Azure Key Vault
- **Rate Limiting**: Configurable request throttling
- **CORS Protection**: Restricted origins

#### **🛡️ SQL Security**  
- **Azure AD Authentication**: Managed identity for SQL access
- **SELECT-Only**: read_data tool restricted to SELECT queries
- **Connection Pooling**: Efficient database connections
- **Audit Trail**: All operations logged with user context

#### **🔒 Infrastructure Security**
- **Key Vault Integration**: Secrets managed securely
- **Managed Identity**: No stored credentials
- **Container Security**: Non-root Docker user
- **Network Security**: Container Apps built-in protection

## 🧪 Advanced Customization

### Add Custom Business Logic

```typescript
// In app/src/tools/custom-tool.ts
export class CustomBusinessTool implements McpTool {
  name = "calculate_revenue";
  
  async execute(args: any): Promise<any> {
    // Your business logic here
    const { startDate, endDate, region } = args;
    
    const query = `
      SELECT SUM(TotalDue) as Revenue
      FROM SalesLT.SalesOrderHeader 
      WHERE OrderDate BETWEEN @startDate AND @endDate
      AND ShipToAddress LIKE '%${region}%'
    `;
    
    return await this.database.query(query, { startDate, endDate });
  }
}
```

### Custom Authentication

```typescript
// In app/src/middleware/custom-auth.ts  
export class CustomAuthMiddleware {
  async authenticate(req: Request): Promise<AuthResult> {
    // Integrate with your identity provider
    // Validate custom tokens, certificates, etc.
  }
}
```

### Multi-Tenant Support

```typescript
// In app/src/database/tenant-router.ts
export class TenantRouter {
  getDatabase(tenantId: string): DatabaseConnection {
    // Route to tenant-specific databases
    return this.connections[tenantId];
  }
}
```

## 📊 Monitoring & Observability

### Application Insights Integration

```bash
# In .env
APPLICATION_INSIGHTS_CONNECTION_STRING=your-connection-string
```

### Health Monitoring

```bash  
# Check MCP server health
curl https://your-mcp-server.azurecontainerapps.io/health

# Detailed server info
curl https://your-mcp-server.azurecontainerapps.io/info
```

### Logging

All operations include:
- **Request ID**: Trace requests end-to-end
- **User Context**: API key authentication details
- **Performance Metrics**: Query execution times
- **Error Details**: Structured error information

## 🔄 Development Workflow

### Local Development

```bash
# 1. Run SQL Server locally (optional)
cd local
docker-compose up -d

# 2. Install dependencies
cd ../app
npm install

# 3. Configure local environment
cp ../.env.example ../.env
# Edit .env for local database

# 4. Build and run
npm run build
npm run dev

# 5. Test locally
curl http://localhost:3000/health
```

### Container Development

```bash
# Build container locally
cd app
docker build -t mcp-sql-server .

# Run container
docker run -p 3000:3000 --env-file ../.env mcp-sql-server

# Test container
curl http://localhost:3000/health
```

## 🎯 Production Considerations

### **Scaling**
- **Horizontal**: Multiple Container App replicas
- **Vertical**: CPU and memory scaling rules  
- **Database**: Connection pooling and read replicas

### **High Availability**
- **Multi-Region**: Deploy in multiple Azure regions
- **Failover**: Automatic Container Apps failover
- **Database**: SQL Database built-in HA

### **Performance**  
- **Caching**: Redis for query result caching
- **CDN**: Static asset delivery
- **Monitoring**: Application Performance Monitoring

### **Compliance**
- **Data Residency**: Choose appropriate Azure regions
- **Encryption**: TLS in transit, encryption at rest
- **Audit**: Comprehensive logging for compliance

## 🆘 Troubleshooting

### ❌ MCP Server Not Starting

```bash
# Check container logs
az containerapp logs show --name your-mcp-server --resource-group your-rg

# Check environment variables
az containerapp show --name your-mcp-server --resource-group your-rg --query "properties.configuration.secrets"
```

### ❌ SQL Connection Issues

```bash
# Verify managed identity has database access
# In Azure Portal Query Editor:
SELECT name, type_desc, authentication_type_desc
FROM sys.database_principals  
WHERE type = 'E'  -- External (managed identity) users
```

### ❌ Agent Can't Connect to MCP Server

```bash
# Test MCP endpoint directly
curl -H "x-api-key: your-api-key" https://your-mcp-server.azurecontainerapps.io/info

# Check API key in Key Vault
az keyvault secret show --vault-name your-keyvault --name mcp-api-key
```

---

## 🚀 Next Steps

1. **🌟 Enhance Tools** - Add custom business logic and data transformations
2. **🔗 Multi-Database** - Connect to multiple databases or data sources  
3. **🤝 Combine MCPs** - Use both external and internal MCP servers in one agent
4. **📈 Monitor Usage** - Set up comprehensive monitoring and alerting

## 💡 Pro Tips

- **Start Simple** - Begin with basic SQL tools, add complexity gradually
- **Security First** - Always use managed identity and Key Vault for production
- **Test Thoroughly** - Use the provided test suite and add your own scenarios
- **Monitor Performance** - Set up alerts for response times and error rates
- **Document Tools** - Provide clear descriptions for agent instructions

---

**🎉 Congratulations!** You now have a production-ready, self-hosted MCP server powering intelligent SQL agents.