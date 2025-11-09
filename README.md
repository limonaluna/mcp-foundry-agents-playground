# Multi-Agent MCP Architecture with Azure AI Foundry

This repository showcases how **Azure AI Foundry Agent Service** can leverage both **internal (self-hosted)** and **external** Model Context Protocol (MCP) servers to create powerful, specialized AI agents.

## 🎯 What This Demonstrates

### **Two MCP Integration Patterns**

1. **🐙 External MCP** - Connect to third-party MCP services (GitHub, APIs, etc.)
2. **🗄️ Internal MCP** - Deploy your own MCP server with custom tools

### **Real-World Example: Multi-Agent SQL + GitHub Assistant**

- **GitHub Agent** → External MCP → Azure REST API specs repository
- **SQL Agent** → Internal MCP → Your Azure SQL Database

Both agents coexist in the same Azure AI Foundry project, giving users access to both code search and database query capabilities.

## 🚀 Architecture Overview

```mermaid
graph TB
    subgraph "Azure AI Foundry Project"
        GA[GitHub Agent]
        SA[SQL Agent]
    end
    
    subgraph "External MCP"
        EXT[gitmcp.io/Azure/azure-rest-api-specs]
    end
    
    subgraph "Your Infrastructure"
        MCPS[MCP Server<br/>Container App]
        SQL[(Azure SQL Database)]
    end
    
    GA -->|search_azure_rest_api_code| EXT
    SA -->|list_table, describe_table, read_data| MCPS
    MCPS -->|Azure AD Auth| SQL
```

## 🚀 Getting Started

Choose your implementation path based on your needs:

### **🟢 External MCP** - Quick & Easy (< 15 minutes)
Perfect for getting started or integrating with existing services.
- **Guide:** [External MCP Setup](docs/EXTERNAL_MCP.md)
- **Infrastructure:** Azure AI Foundry + Model deployment only
- **Benefits:** Connect to GitHub APIs, web services, no server deployment
- **Limitation:** Restricted to available external services

### **🔵 Self-Hosted MCP** - Full Control (15-30 minutes)  
Build custom tools with complete control over functionality and data.
- **Guide:** [Self-Hosted MCP Setup](docs/SELF_HOSTED_MCP.md)
- **Infrastructure:** Azure AI Foundry + Model + SQL Server + Container Apps + Key Vault
- **Benefits:** Custom business logic, enterprise security, unlimited capabilities
- **Trade-off:** Requires infrastructure deployment and maintenance



## 📊 Comparison

| Aspect | External MCP | Self-Hosted MCP |
|--------|-------------|-----------------|
| **Setup Time** | < 15 minutes | 15-30 minutes |
| **Azure Infrastructure** | Azure AI Foundry + Model | Azure AI Foundry + Model + SQL Server + Container Apps + Key Vault |
| **Security** | No authentication required | API Key authentication |
| **Playground Testing** | ❌ Limited UI support for tool approvals | ❌ SDK only (API auth limitation) |

## 🎬 Testing Your Agents

### **🤖 Interactive Chat Playgrounds**

Experience your agents just like in the Azure AI Foundry UI with interactive chat sessions:

```bash
cd test

# Chat with GitHub Agent (External MCP)
python chat-with-github-agent.py
# 🗨️ Interactive conversation with GitHub repository search
# 💬 Type your questions and get real-time responses
# 🔧 Automatic tool usage detection and approval

# Chat with SQL Agent (Self-Hosted MCP)
python chat-with-sql-agent.py  
# 🗨️ Interactive database queries and exploration
# 💾 Real-time SQL operations with formatted results
# 🔧 Automatic tool approval for seamless experience
```

**Chat Commands:**
- `quit`/`exit`/`bye` - End the chat session
- `help` - Show example queries for each agent  
- `clear` - Start a new conversation thread

### **📋 Automated Test Scripts**

Run comprehensive test suites with predefined scenarios for validation:

```bash
cd test

# Test GitHub Agent (External MCP)
python test-github-agent.py
# ✅ 4 automated scenarios testing repository search capabilities
# ✅ Tool call detection with response content analysis
# ✅ No MCP server infrastructure required

# Test SQL Agent (Self-Hosted MCP)  
python test-sql-agent.py
# ✅ 4 automated scenarios testing database operations
# ✅ Table listing, schema inspection, and data querying
# ✅ Full control over tools and security
```

**Test Script Features:**
- **Non-interactive** - Runs predefined test scenarios automatically
- **Comprehensive coverage** - Tests basic capabilities, tool usage, and specific queries
- **Detailed reporting** - Shows success/failure status and tool call evidence
- **CI/CD friendly** - Perfect for automated validation pipelines

### ✅ Success Indicators

**GitHub Agent Working Correctly:**
When your GitHub MCP agent is properly configured, you'll see:
```
mcp_github: Allows searching for code and files within the GitHub repository 
for Azure REST API specifications (Azure/azure-rest-api-specs).
```

**Example Queries to Try:**
- "Search for authentication examples in Azure REST APIs"
- "Find Storage Account REST API schemas"  
- "Show me examples of Azure Resource Manager templates"
- "Look for Key Vault API specifications"

### 🔧 Troubleshooting

**"RequiresAction" Error - UI Limitation:**

Even after configuring `require_approval="never"`, the Azure AI Foundry UI still requires manual approval for MCP tool calls.

**❌ Current UI Limitation:**
- The Azure AI Foundry playground UI overrides agent-level approval settings
- Tool calls always go into "RequiresAction" status in the UI
- This appears to be a current limitation of the web interface

**✅ Working Solutions:**

**Option 1 - Use the Test Script (Recommended):**
```bash
cd test
python test-github-agent.py
```
- Bypasses UI limitations entirely
- Shows actual MCP tool functionality and results
- Configured with `require_approval="never"` for seamless operation

**Option 2 - Use VS Code Extension:**
- Install the Azure AI Foundry VS Code extension
- May provide better MCP tool approval experience
- See [VS Code MCP integration guide](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/develop/vs-code-agents-mcp)

**Tool Call Timeouts:**
- External MCP servers may have rate limits
- Wait a few seconds between requests
- Some external services may be temporarily unavailable

## 🔗 Additional Resources

- **[Configuration Guide](docs/CONFIGURATION.md)** - Environment variables and config files
- **[Local Development](local/README.md)** - Docker-based local testing  
- **[Node.js Version](../Node/README.md)** - VS Code MCP integration (stdio)

---



*Built with ❤️ for the Azure AI Community*
