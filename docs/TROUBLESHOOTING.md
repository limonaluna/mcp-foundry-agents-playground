# Troubleshooting Guide

This guide helps you resolve common issues when working with MCP agents in Azure AI Foundry.

## 🚨 Common Issues

### **"RequiresAction" Error - UI Limitation**

Even after configuring `require_approval="never"`, the Azure AI Foundry UI still requires manual approval for MCP tool calls.

#### **❌ Current UI Limitation:**
- The Azure AI Foundry playground UI overrides agent-level approval settings
- Tool calls always go into "RequiresAction" status in the UI
- This appears to be a current limitation of the web interface

#### **✅ Working Solutions:**

**Option 1 - Use the Interactive Chat Scripts (Recommended):**
```bash
cd test

# For GitHub Agent
python chat-with-github-agent.py

# For SQL Agent  
python chat-with-sql-agent.py
```
- Bypasses UI limitations entirely
- Shows actual MCP tool functionality and results
- Configured with automatic tool approval for seamless operation
- Provides the same interactive experience as the Azure AI Foundry UI

**Option 2 - Use the Automated Test Scripts:**
```bash
cd test

# For GitHub Agent
python test-github-agent.py

# For SQL Agent
python test-sql-agent.py
```
- Non-interactive validation with predefined scenarios
- Perfect for confirming your agents are working correctly
- Shows detailed tool call detection and evidence

**Option 3 - Use VS Code Extension:**
- Install the Azure AI Foundry VS Code extension
- May provide better MCP tool approval experience  
- See [VS Code MCP integration guide](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/vs-code-agents-mcp)

### **Tool Call Timeouts**

**Symptoms:**
- Agent runs timeout or fail to complete
- "Waiting for response" messages that never resolve
- Intermittent failures

**Solutions:**
- **External MCP servers** may have rate limits - wait a few seconds between requests
- **Network connectivity** - some external services may be temporarily unavailable
- **Authentication issues** - verify API keys and credentials are valid
- **Increase timeouts** in your agent configuration if possible

### **GitHub Agent Issues**

**Agent Not Found:**
```
❌ Agent 'github-mcp-agent' not found.
```
**Solution:** Deploy the agent first:
```bash
cd infrastructure/agents
python mcp-github-agent.py
```

**External MCP Server Unavailable:**
```
❌ Failed to connect to https://gitmcp.io/Azure/azure-rest-api-specs
```
**Solutions:**
- Check if the external service is operational
- Verify network connectivity
- Try again later (external services may have temporary outages)
- Consider rate limiting delays

**No Tool Calls Detected:**
```
✅ SUCCESS
   No tool calls detected
```
**This is actually normal!** With `require_approval="never"`, tools execute automatically. The chat scripts use response content analysis to detect tool usage:
- Look for "🔧 Tool usage detected via response analysis!"  
- Responses with specific GitHub URLs and file paths indicate successful tool calls

### **SQL Agent Issues**

**Agent Run Failures:**
```
❌ Run failed with status: RunStatus.FAILED
```
**Common causes:**
1. **Network restrictions** - Add your IP to the Container App ingress rules
2. **SQL authentication** - Verify managed identity permissions
3. **API key issues** - Check Key Vault access and valid API key

**Connection Errors:**
```
❌ Connection error: McpTool.__init__() got an unexpected keyword argument 'headers'
```
**Solution:** This was fixed in recent versions. Make sure you're using the latest code:
```bash
git pull origin main
```

**Database Access Denied:**
```
Error: Failed to enumerate tools from remote server: Response status code does not indicate success: 400 (Bad Request)
```
**Solutions:**
1. **Check IP restrictions:**
   - Add your current IP to the Container App ingress rules
   - Verify the Container App is accessible from your location

2. **Verify API key:**
   ```bash
   # Test the MCP server endpoint directly
   curl -H "X-API-Key: your-key" https://your-mcp-server.azurecontainerapps.io/health
   ```

3. **Check managed identity permissions:**
   - Ensure the Container App's managed identity has SQL database access
   - Verify the managed identity is granted appropriate SQL roles

### **Authentication Issues**

**Azure CLI Not Authenticated:**
```
❌ Failed to load configuration: DefaultAzureCredential failed to retrieve a token
```
**Solution:**
```bash
az login
az account set --subscription "your-subscription-id"
```

**Key Vault Access Denied:**
```
❌ Failed to retrieve API key from Key Vault
```
**Solutions:**
1. **Check permissions:**
   ```bash
   az keyvault show --name your-keyvault-name
   ```

2. **Grant access:**
   ```bash
   az keyvault set-policy --name your-keyvault-name --upn your-email@domain.com --secret-permissions get list
   ```

3. **Verify secret exists:**
   ```bash
   az keyvault secret show --vault-name your-keyvault-name --name mcp-api-key
   ```

### **Configuration Issues**

**Missing Configuration Files:**
```
❌ Configuration file not found: config/config.json
```
**Solution:** Ensure you have the required configuration files:
- `config/config.json` - Main configuration
- `config/foundry-deployment-outputs.json` - Azure AI Foundry deployment info
- `config/mcp-sql-server-deployment-outputs.json` - SQL MCP server info (if using SQL agent)

**Invalid Configuration:**
```
❌ Failed to parse configuration
```
**Solution:** Validate your JSON configuration files:
```bash
# Check JSON syntax
python -m json.tool config/config.json
```

## 🔍 Diagnostic Commands

### **Test Network Connectivity**
```bash
# Test GitHub MCP server
curl -s https://gitmcp.io/Azure/azure-rest-api-specs

# Test SQL MCP server health
curl -H "X-API-Key: your-key" https://your-mcp-server.azurecontainerapps.io/health
```

### **Verify Azure Authentication**
```bash
# Check current Azure account
az account show

# Test Key Vault access
az keyvault secret list --vault-name your-keyvault-name

# Test SQL database access token
az account get-access-token --resource https://database.windows.net/
```

### **Check Agent Status**
```bash
# List all agents in your project
cd test
python -c "
from config_utils import get_project_config
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

config = get_project_config()
client = AIProjectClient(endpoint=config['endpoint'], credential=DefaultAzureCredential())
agents = client.agents.list()
for agent in agents:
    print(f'Agent: {agent.name} (ID: {agent.id})')
"
```

## 📞 Getting Help

If you're still experiencing issues:

1. **Check the logs:**
   - Azure Container Apps logs for SQL MCP server issues
   - Local terminal output for detailed error messages

2. **Verify prerequisites:**
   - Azure CLI authentication
   - Required Azure resources deployed
   - Network connectivity to external services

3. **Use the diagnostic commands** above to isolate the issue

4. **Try the working solutions** (chat scripts and test scripts) to confirm functionality

5. **Review the configuration guides:**
   - [Configuration Guide](CONFIGURATION.md)
   - [MCP Server Guide](MCP_SERVER.md)

Remember: The interactive chat scripts (`chat-with-*-agent.py`) provide the best experience and work around most Azure AI Foundry UI limitations! 🚀

---

*Most issues can be resolved by using the chat scripts instead of the Azure AI Foundry UI playground.*