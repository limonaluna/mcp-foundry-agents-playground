# External MCP Integration Guide

Connect Azure AI Foundry agents to third-party MCP services for instant capabilities.

## 🎯 What You'll Build

A **GitHub Agent** that can search the Azure REST API specifications repository using an external MCP service.

- **Setup Time**: < 15 minutes
- **Azure Infrastructure**: Azure AI Foundry + Model Deployment
- **MCP Infrastructure**: Zero deployment needed (uses external service)
- **Tools**: `search_azure_rest_api_code`

## 🏗️ Architecture

```
┌─────────────────────┐
│  Azure AI Foundry   │
│    GitHub Agent     │
└──────────┬──────────┘
           │ MCP Protocol
           ▼
┌─────────────────────┐
│   External MCP      │
│  gitmcp.io Service  │
│                     │
│ Azure/azure-rest-   │
│ api-specs repo      │
└─────────────────────┘
```

## 📋 Prerequisites

- **Azure AI Foundry** (Hub and Project) with model deployment
- Python environment with required packages
- No MCP server infrastructure needed (uses external service)

## 🚀 Quick Start

### Step 1: Setup Azure AI Foundry (if needed)

```bash
# Deploy Foundry Hub and Project
cd infrastructure/foundry
.\deploy.ps1
```

### Step 2: Install Dependencies

```bash
# Install Python packages for agent deployment
pip install -r requirements.txt
```

### Step 3: Deploy GitHub Agent

```bash
# Deploy the GitHub agent
cd infrastructure/agents
python mcp-github-agent.py
```

**Output:**
```
✓ Agent creating successfully!
Agent Details:
  ID:           asst_qwvqgiNUMBNy7ZdOYdEVo3RK
  Name:         github-mcp-agent
  MCP Server:   https://gitmcp.io/Azure/azure-rest-api-specs
```

### Step 4: Test the Agent

**Option A: Automated Test Suite**
```bash
# Run comprehensive tests
cd ../../test
python test-github-agent.py
```

**Option B: Interactive Testing in Azure AI Foundry**
1. Navigate to [Azure AI Foundry](https://ai.azure.com)
2. Open your project → **Agents** → **github-mcp-agent**
3. Click **Test in playground**
4. Try queries like:
   - "Search for authentication examples in Azure REST APIs"
   - "Find rate limiting documentation"
   - "Show me examples of error handling"

## 🛠️ Available Tools

### `search_azure_rest_api_code`

Search for code, files, or documentation in the Azure REST API specifications repository.

**Example Usage:**
```json
{
  "query": "authentication",
  "page": 1
}
```

**Response:**
- File paths and snippets containing "authentication"
- Direct links to GitHub repository files
- Context around search matches

## 🔧 Configuration

The GitHub agent configuration is in `config/config.json`:

```json
{
  "agents": {
    "github": {
      "name": "github-mcp-agent",
      "instructions": "You are a helpful agent that can search Azure REST API specifications...",
      "mcpServer": {
        "url": "https://gitmcp.io/Azure/azure-rest-api-specs",
        "label": "github",
        "authType": "none"
      },
      "allowedTools": ["search_azure_rest_api_code"]
    }
  }
}
```

## 🧪 Test Scenarios

The test suite covers:

1. **Agent Capabilities** - Verify agent describes its GitHub search abilities
2. **Available Tools** - Confirm `mcp_github` tool is accessible
3. **Tool Usage** - Perform actual search and validate results

**Expected Results:**
```
✅ Scenario 1: Agent Capabilities (no tools)
✅ Scenario 2: Available Tools (no tools)  
✅ Scenario 3: Tool Usage (1 tool calls)
```

## 🌐 Other External MCP Services

The same pattern works for other external MCP servers:

### Web Search
```json
{
  "mcpServer": {
    "url": "https://mcp-search-api.com",
    "authType": "apiKey"
  }
}
```

### REST APIs
```json
{
  "mcpServer": {
    "url": "https://api-mcp-bridge.com/your-api",
    "authType": "bearer"
  }
}
```

### Public Repositories
```json
{
  "mcpServer": {
    "url": "https://gitmcp.io/microsoft/typescript",
    "authType": "none"
  }
}
```

## 🎯 Benefits of External MCP

### ✅ **Simplified Infrastructure**
- No MCP server infrastructure to manage
- No container apps, databases, or storage accounts for MCP
- Still requires Azure AI Foundry and model deployment
- Just agent configuration and deployment for MCP integration

### ✅ **Ecosystem Access**
- Tap into growing MCP service ecosystem
- Pre-built integrations for popular services
- Community-maintained tools and connectors

### ✅ **Cost Effective**
- Zero MCP server infrastructure costs
- Azure AI Foundry costs for hub, project, and model deployment
- No ongoing MCP server maintenance overhead

### ✅ **Rapid Prototyping**
- Test MCP integration patterns quickly
- Validate agent concepts before building custom tools
- Mix and match multiple external services
- **Interactive testing** directly in Azure AI Foundry playground

## 🔄 Next Steps

1. **🎯 [Try Self-Hosted MCP](SELF_HOSTED_MCP.md)** - Build custom tools with full control
2. **🔗 Combine Both** - Use external MCP for quick capabilities, internal for custom logic
3. **🌟 Explore Ecosystem** - Discover more external MCP services at [mcp-directory.com](https://mcp-directory.com)

## 💡 Pro Tips

- **Start External** - Begin with external MCP to understand patterns
- **Tool Restrictions** - Use `allowedTools` to limit agent capabilities
- **Combine Services** - One agent can use multiple MCP servers
- **Fallback Strategy** - Have backup MCP servers for reliability

## 🆘 Troubleshooting

### ❌ Agent Can't Find MCP Server
```bash
# Check if external MCP service is accessible
curl -I https://gitmcp.io/Azure/azure-rest-api-specs
```

### ❌ Tool Not Working
- Verify `allowedTools` includes the tool name
- Check external MCP service documentation for correct tool names

### ❌ Authentication Issues
- Most external MCP services use `authType: "none"`
- Check service documentation for API key requirements

---

**🎉 Congratulations!** You've successfully integrated external MCP services with Azure AI Foundry agents.