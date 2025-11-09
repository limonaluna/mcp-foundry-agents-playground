#!/usr/bin/env python3
"""
Interactive chat with GitHub MCP Agent - mimics Azure AI Foundry UI experience
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
    print("=" * 80)
    print("🤖 Interactive Chat with GitHub MCP Agent")
    print("=" * 80)
    print("This mimics the Azure AI Foundry UI experience.")
    print("Type your questions and get responses with GitHub repository access!")
    print()
    print("Commands:")
    print("  - Type 'quit', 'exit', or 'bye' to end the chat")
    print("  - Type 'help' to see example queries")
    print("  - Type 'clear' to start a new conversation thread")
    print("=" * 80)
    print()

def print_help():
    print("💡 Example Queries:")
    print()
    print("📁 File Search:")
    print("  • Find files containing 'KeyVault' in the Azure REST API specs")
    print("  • Search for Storage Account API endpoints")
    print("  • Look for authentication-related APIs")
    print()
    print("🔍 Specific Searches:")
    print("  • Show me the API for creating a Key Vault")
    print("  • Find the latest version of the Compute API")
    print("  • What are the endpoints for Azure SQL Database?")
    print()
    print("📊 Repository Info:")
    print("  • How many different Azure services have REST APIs?")
    print("  • What's the structure of the repository?")
    print("  • Find deprecated APIs")
    print()

def wait_for_run_completion(agents_client, thread_id, run_id, show_progress=True):
    """Wait for run to complete and handle any tool approvals"""
    attempt = 0
    max_attempts = 120  # 2 minutes max
    
    while True:
        time.sleep(1)
        attempt += 1
        run = agents_client.runs.get(thread_id=thread_id, run_id=run_id)
        
        if show_progress and attempt % 5 == 0:
            print(f"  [Thinking... {attempt}s]", end='\r')
        
        if run.status == "completed":
            if show_progress:
                print(" " * 20, end='\r')  # Clear progress
            return run
        elif run.status == "failed":
            print(f"\n❌ Run failed: {run.last_error}")
            return run
        elif run.status == "requires_action":
            # Handle tool approvals (shouldn't happen with require_approval="never")
            if run.required_action:
                print("\n🔧 Processing tool calls...")
                # Auto-approve any required tool calls
                if hasattr(run.required_action, 'submit_mcp_tool_approval'):
                    required_calls = run.required_action.submit_mcp_tool_approval.required_mcp_tool_calls
                    tool_approvals = [
                        ToolApproval(call_id=call.id, approve=True)
                        for call in required_calls
                    ]
                    
                    agents_client.runs.submit_tool_approval(
                        thread_id=thread_id,
                        run_id=run_id,
                        tool_approval_action=SubmitToolApprovalAction(tool_approvals=tool_approvals)
                    )
        elif run.status in ["cancelled", "expired"]:
            print(f"\n⚠ Run {run.status}")
            return run
        
        if attempt >= max_attempts:
            print(f"\n⚠ Timeout after {max_attempts} seconds")
            return run

def get_latest_response(agents_client, thread_id):
    """Get the latest assistant response from the thread"""
    messages = agents_client.messages.list(
        thread_id=thread_id,
        order=ListSortOrder.DESCENDING,
        limit=1
    )
    
    for message in messages:
        if message.role == "assistant" and message.text_messages:
            return message.text_messages[0].text.value
    
    return None

def analyze_tool_usage(response_text):
    """Analyze response for evidence of tool usage"""
    if not response_text:
        return False, []
    
    tool_indicators = [
        "github.com/Azure/azure-rest-api-specs",
        "specification/",
        "blob/",
        "api-version",
        "Microsoft.KeyVault",
        "Microsoft.Storage",
        "Microsoft.Compute",
        "routes.tsp",
        "main/specification"
    ]
    
    found_indicators = [indicator for indicator in tool_indicators if indicator.lower() in response_text.lower()]
    return len(found_indicators) >= 2, found_indicators

def main():
    print_header()
    
    # Load configuration
    try:
        project_config = get_project_config()
        agent_config = get_agent_config("github")
        print("✓ Configuration loaded")
    except Exception as e:
        print(f"❌ Failed to load configuration: {e}")
        return 1
    
    print(f"🔗 Connected to: {project_config['endpoint'].split('/')[-2]}")
    print(f"🤖 Agent: {agent_config['name']}")
    print(f"📂 Repository: Azure/azure-rest-api-specs")
    print()
    
    # Connect to Azure AI Foundry
    try:
        project_client = AIProjectClient(
            endpoint=project_config["endpoint"],
            credential=DefaultAzureCredential(),
        )
        print("✓ Connected to Azure AI Foundry")
    except Exception as e:
        print(f"❌ Failed to connect: {e}")
        return 1
    
    try:
        with project_client:
            agents_client = project_client.agents
            
            # Find agent
            print("🔍 Looking up agent...")
            agent_id = find_agent_by_name(agents_client, agent_config["name"])
            
            if not agent_id:
                print(f"❌ Agent '{agent_config['name']}' not found.")
                return 1
            
            print(f"✓ Found agent: {agent_id}")
            
            # Initialize MCP tool
            mcp_tool = McpTool(
                server_label=agent_config["mcpServer"]["label"],
                server_url=agent_config["mcpServer"]["url"],
                allowed_tools=[],
            )
            mcp_tool.set_approval_mode("never")
            
            # Create initial thread
            print("🧵 Creating conversation thread...")
            thread = agents_client.threads.create()
            print(f"✓ Thread ready: {thread.id}")
            print()
            
            print("🎯 Ready to chat! Type your questions below:")
            print("-" * 80)
            
            # Main chat loop
            message_count = 0
            
            while True:
                try:
                    # Get user input
                    user_input = input("\n💬 You: ").strip()
                    
                    if not user_input:
                        continue
                    
                    # Handle special commands
                    if user_input.lower() in ['quit', 'exit', 'bye']:
                        print("\n👋 Goodbye!")
                        break
                    elif user_input.lower() == 'help':
                        print_help()
                        continue
                    elif user_input.lower() == 'clear':
                        print("\n🧹 Starting new conversation thread...")
                        thread = agents_client.threads.create()
                        message_count = 0
                        print(f"✓ New thread ready: {thread.id}")
                        continue
                    
                    # Send message to agent
                    print("\n🤖 Assistant: ", end="", flush=True)
                    
                    message = agents_client.messages.create(
                        thread_id=thread.id,
                        role="user",
                        content=user_input
                    )
                    message_count += 1
                    
                    # Create run
                    run = agents_client.runs.create(
                        thread_id=thread.id,
                        agent_id=agent_id,
                        tool_resources=mcp_tool.resources
                    )
                    
                    # Wait for completion
                    completed_run = wait_for_run_completion(agents_client, thread.id, run.id)
                    
                    if completed_run.status == "completed":
                        # Get response
                        response = get_latest_response(agents_client, thread.id)
                        
                        if response:
                            print(response)
                            
                            # Analyze for tool usage
                            used_tools, indicators = analyze_tool_usage(response)
                            if used_tools:
                                print(f"\n🔧 Tool used: GitHub repository search")
                                print(f"   Evidence: {', '.join(indicators[:2])}...")
                        else:
                            print("(No response received)")
                    else:
                        print(f"❌ Request failed: {completed_run.status}")
                        if completed_run.last_error:
                            print(f"   Error: {completed_run.last_error}")
                
                except KeyboardInterrupt:
                    print(f"\n\n⚠ Interrupted by user")
                    break
                except Exception as e:
                    print(f"\n❌ Error: {e}")
                    continue
            
    except Exception as e:
        print(f"❌ Session error: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())