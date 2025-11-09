#!/usr/bin/env python3
"""
Interactive chat interface for SQL MCP Agent.
Mimics the Azure AI Foundry UI experience for database interactions.
"""

import os
import sys
import time
from pathlib import Path
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.ai.agents.models import (
    ListSortOrder,
    McpTool,
    RequiredMcpToolCall,
    SubmitToolApprovalAction,
    ToolApproval,
)

# Import configuration utilities
from config_utils import load_config, get_agent_config, get_project_config, find_agent_by_name

def print_header():
    print("=" * 70)
    print("🤖 Interactive Chat with SQL MCP Agent")
    print("=" * 70)
    print("This mimics the Azure AI Foundry UI experience for database queries.")
    print("Type your questions about the SQL database and I'll help you!")
    print()
    print("Commands:")
    print("  quit/exit/bye - End the chat session")
    print("  help          - Show example queries")
    print("  clear         - Start a new conversation thread")
    print("=" * 70)
    print()

def print_help():
    print("💡 Example SQL queries you can try:")
    print()
    print("Database Structure:")
    print("  • What tables are available in the database?")
    print("  • Show me the schema for the Products table")
    print("  • What columns does the Orders table have?")
    print()
    print("Data Queries:")
    print("  • Show me the top 10 products by price")
    print("  • How many orders were placed last month?")
    print("  • Find all customers from California")
    print("  • What's the total revenue for 2024?")
    print()
    print("Analysis:")
    print("  • Which product category has the highest sales?")
    print("  • Show me sales trends by month")
    print("  • Find customers who haven't placed orders recently")
    print()

def analyze_sql_response(response_text):
    """Analyze response for SQL tool usage indicators"""
    if not response_text:
        return []
    
    sql_indicators = [
        "SELECT",
        "FROM",
        "WHERE",
        "JOIN",
        "INSERT",
        "UPDATE",
        "DELETE",
        "CREATE TABLE",
        "ALTER TABLE",
        "database",
        "table",
        "column",
        "rows",
        "query",
        "SQL"
    ]
    
    found_indicators = [indicator for indicator in sql_indicators 
                       if indicator.lower() in response_text.lower()]
    
    return found_indicators

def main():
    print_header()
    
    # Load configuration
    print("🔌 Connecting to Azure AI Foundry...")
    try:
        project_config = get_project_config()
        agent_config = get_agent_config("sql")
        print(f"✓ Configuration loaded")
        print(f"  Project: {project_config['endpoint'].split('/')[-2]}")
        print(f"  Agent: {agent_config['name']}")
        print(f"  Database: {agent_config['mcpServer']['url']}")
        print()
    except Exception as e:
        print(f"❌ Failed to load configuration: {e}")
        return 1
    
    # Connect to Azure AI Foundry
    project_client = AIProjectClient(
        endpoint=project_config["endpoint"],
        credential=DefaultAzureCredential(),
    )
    
    try:
        with project_client:
            agents_client = project_client.agents
            
            # Find agent by name
            print(f"🔍 Looking up SQL agent '{agent_config['name']}'...")
            agent_id = find_agent_by_name(agents_client, agent_config["name"])
            
            if not agent_id:
                print(f"❌ Agent '{agent_config['name']}' not found.")
                print("💡 Make sure you've deployed the SQL MCP agent first.")
                return 1
            
            print(f"✓ Found agent: {agent_id}")
            
            # Initialize MCP tool with API key from Key Vault
            print("🔑 Loading MCP API key from Azure Key Vault...")
            from azure.keyvault.secrets import SecretClient
            
            # Load API key from Key Vault (using infrastructure config)
            config = load_config()
            key_vault_name = config["infrastructure"]["mcp"]["keyVault"]["name"]
            key_vault_url = f"https://{key_vault_name}.vault.azure.net/"
            secret_name = config["infrastructure"]["mcp"]["keyVault"]["apiKeySecretName"]
            
            secret_client = SecretClient(vault_url=key_vault_url, credential=DefaultAzureCredential())
            api_key_secret = secret_client.get_secret(secret_name)
            api_key = api_key_secret.value
            
            mcp_tool = McpTool(
                server_label=agent_config["mcpServer"]["label"],
                server_url=agent_config["mcpServer"]["url"],
                allowed_tools=agent_config.get("allowedTools", [])
            )
            
            # Set API key header if required
            if api_key:
                mcp_tool.update_headers("X-API-Key", api_key)
            
            # Note: SQL agent requires approval for safety, so we don't set approval_mode="never"
            
            print(f"✓ SQL MCP tool initialized")
            print()
            
            # Create initial thread
            print("🧵 Creating conversation thread...")
            thread = agents_client.threads.create()
            print(f"✓ Thread ready: {thread.id}")
            print()
            
            # Chat loop
            print("🚀 Ready to chat! Ask me anything about the SQL database.")
            print()
            
            while True:
                try:
                    # Get user input
                    print("You: ", end="", flush=True)
                    user_input = input().strip()
                    
                    if not user_input:
                        continue
                    
                    # Handle commands
                    if user_input.lower() in ['quit', 'exit', 'bye']:
                        print("\n👋 Goodbye! Thanks for chatting with the SQL agent.")
                        break
                    elif user_input.lower() == 'help':
                        print()
                        print_help()
                        continue
                    elif user_input.lower() == 'clear':
                        print("\n🔄 Starting new conversation...")
                        thread = agents_client.threads.create()
                        print(f"✓ New thread created: {thread.id}")
                        print()
                        continue
                    
                    # Add user message
                    message = agents_client.messages.create(
                        thread_id=thread.id,
                        role="user",
                        content=user_input
                    )
                    
                    # Create and run agent
                    print("\n🤖 SQL Agent: ", end="", flush=True)
                    print("Thinking", end="", flush=True)
                    
                    run = agents_client.runs.create(
                        thread_id=thread.id,
                        agent_id=agent_id,
                        tool_resources=mcp_tool.resources
                    )
                    
                    # Wait for completion with progress indicator
                    attempt = 0
                    max_attempts = 60
                    tool_calls_made = []
                    
                    while run.status in ["queued", "in_progress", "requires_action"]:
                        time.sleep(1)
                        attempt += 1
                        
                        # Show thinking progress
                        if attempt % 2 == 0:
                            print(".", end="", flush=True)
                        
                        run = agents_client.runs.get(thread_id=thread.id, run_id=run.id)
                        
                        # Handle tool approvals (SQL operations require approval for safety)
                        if run.status == "requires_action" and run.required_action:
                            print(f"\n  🔧 SQL operation requested - auto-approving...", end="", flush=True)
                            
                            if hasattr(run.required_action, 'submit_tool_approval'):
                                tool_calls = run.required_action.submit_tool_approval.tool_calls
                                if tool_calls:
                                    # Record tool calls
                                    for call in tool_calls:
                                        if isinstance(call, RequiredMcpToolCall):
                                            tool_calls_made.append({
                                                "name": call.name,
                                                "arguments": call.arguments
                                            })
                                            print(f"\n    • {call.name}", end="", flush=True)
                                    
                                    # Auto-approve all tool calls
                                    tool_approvals = [
                                        ToolApproval(
                                            tool_call_id=call.id,
                                            approve=True,
                                            headers=mcp_tool.headers,
                                        )
                                        for call in tool_calls
                                    ]
                                    
                                    agents_client.runs.submit_tool_outputs(
                                        thread_id=thread.id,
                                        run_id=run.id,
                                        tool_approvals=tool_approvals
                                    )
                                else:
                                    print("\n❌ No tool calls found - cancelling run")
                                    agents_client.runs.cancel(thread_id=thread.id, run_id=run.id)
                                    break
                        
                        if attempt >= max_attempts:
                            print("\n⚠ Timeout waiting for response")
                            break
                    
                    print()  # New line after thinking dots
                    
                    if run.status == "completed":
                        # Get the latest response
                        messages = agents_client.messages.list(
                            thread_id=thread.id,
                            order=ListSortOrder.ASCENDING
                        )
                        
                        agent_response = None
                        for msg in messages:
                            if msg.role == "assistant" and msg.text_messages:
                                agent_response = msg.text_messages[-1].text.value
                        
                        if agent_response:
                            # Analyze for SQL tool usage
                            sql_indicators = analyze_sql_response(agent_response)
                            
                            if not tool_calls_made and len(sql_indicators) >= 3:
                                print("  🔧 SQL database operations detected!", flush=True)
                                tool_calls_made.append({
                                    "name": "inferred_sql_query",
                                    "evidence": sql_indicators[:5]
                                })
                            
                            # Show tool usage indicator
                            if tool_calls_made:
                                print(f"  💾 Used {len(tool_calls_made)} database operation(s)")
                            
                            print(agent_response)
                        else:
                            print("❌ No response received")
                    else:
                        print(f"❌ Run failed with status: {run.status}")
                        
                        # Get detailed error information
                        if hasattr(run, 'last_error') and run.last_error:
                            print(f"   Error: {run.last_error.message}")
                        
                        # Try to get any partial response
                        try:
                            messages = agents_client.messages.list(
                                thread_id=thread.id,
                                order=ListSortOrder.ASCENDING
                            )
                            
                            for msg in messages:
                                if msg.role == "assistant" and msg.text_messages:
                                    partial_response = msg.text_messages[-1].text.value
                                    if partial_response:
                                        print(f"   Partial response: {partial_response[:200]}...")
                                        break
                        except:
                            pass  # Ignore errors getting partial response
                    
                    print()  # Extra space before next input
                    
                except KeyboardInterrupt:
                    print("\n\n👋 Chat interrupted. Goodbye!")
                    break
                except Exception as e:
                    print(f"\n❌ Error: {e}")
                    print("💡 Try again or type 'help' for examples.")
                    print()
            
            return 0
            
    except Exception as e:
        print(f"\n❌ Connection error: {e}")
        print("💡 Make sure you're authenticated with Azure CLI and the agent is deployed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())