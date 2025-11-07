"""
Test Azure AI Foundry SQL MCP agent.

This comprehensive test verifies:
1. MCP server connection
2. Agent capabilities
3. Database table listing
4. Schema inspection
5. Data querying

Uses centralized configuration and dynamic agent lookup.

Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/model-context-protocol-samples?pivots=python
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
from config_utils import load_config, get_agent_config, get_project_config, find_agent_by_name, get_mcp_api_key

# Test scenarios
TEST_SCENARIOS = [
    {
        "name": "Agent Capabilities",
        "query": "What can you do? Please describe your capabilities.",
        "description": "Test basic agent response without tool usage"
    },
    {
        "name": "List Database Tables",
        "query": "List all tables in the database.",
        "description": "Test listing all tables using MCP tool"
    },
    {
        "name": "Describe Table Schema",
        "query": "Describe the schema of the SalesLT.Customer table.",
        "description": "Test table schema inspection"
    },
    {
        "name": "Query Customer Data",
        "query": "Show me the first 5 customers from the SalesLT.Customer table.",
        "description": "Test data querying capabilities"
    }
]


def main():
    print("=" * 70)
    print("COMPREHENSIVE SQL MCP Agent Test Suite")
    print("=" * 70)
    print()
    
    # Load configuration
    print("Loading configuration...")
    try:
        project_config = get_project_config()
        agent_config = get_agent_config("sql")
        print(f"✓ Configuration loaded")
        print()
    except Exception as e:
        print(f"❌ Failed to load configuration: {e}")
        return 1
    
    print(f"Configuration:")
    print(f"  Project Endpoint: {project_config['endpoint']}")
    print(f"  Agent Name:       {agent_config['name']}")
    print(f"  MCP Server:       {agent_config['mcpServer']['url']}")
    print(f"  Server Label:     {agent_config['mcpServer']['label']}")
    print()
    
    # Get MCP API key if required
    api_key = None
    if agent_config["mcpServer"]["authType"] == "apiKey":
        print("Loading MCP API key from Azure Key Vault...")
        try:
            # get_mcp_api_key will try Key Vault first, then fallback to file
            api_key = get_mcp_api_key()
            print("✓ API key loaded")
        except ValueError as e:
            print(f"❌ {e}")
            return 1
        print()
    
    # Step 1: Connect to Azure AI Foundry
    print("=" * 70)
    print("STEP 1: Connecting to Azure AI Foundry")
    print("=" * 70)
    print("Connecting...")
    project_client = AIProjectClient(
        endpoint=project_config["endpoint"],
        credential=DefaultAzureCredential(),
    )
    print("✓ Connected to project")
    print()
    
    test_results = []
    
    try:
        with project_client:
            agents_client = project_client.agents
            
            # Step 2: Find agent by name
            print("=" * 70)
            print("STEP 2: Looking Up Agent by Name")
            print("=" * 70)
            print(f"Searching for agent: {agent_config['name']}")
            agent_id = find_agent_by_name(agents_client, agent_config["name"])
            
            if not agent_id:
                print(f"❌ Agent '{agent_config['name']}' not found.")
                print(f"   Please run: python deploy/agent/mcp-sql-agent.py")
                return 1
            
            print(f"✓ Found agent: {agent_id}")
            print()
            
            # Step 3: Get agent details
            print("=" * 70)
            print("STEP 3: Retrieving Agent Details")
            print("=" * 70)
            agent = agents_client.get_agent(agent_id)
            print(f"✓ Agent: {agent.name}")
            print(f"  Model: {agent.model}")
            print(f"  Created: {agent.created_at}")
            print()
            
            # Step 4: Initialize MCP tool
            print("=" * 70)
            print("STEP 4: Initializing MCP Tool")
            print("=" * 70)
            mcp_tool = McpTool(
                server_label=agent_config["mcpServer"]["label"],
                server_url=agent_config["mcpServer"]["url"],
                allowed_tools=agent_config.get("allowedTools", []),
            )
            
            # Set API key header if required
            if api_key:
                mcp_tool.update_headers("X-API-Key", api_key)
            
            print(f"✓ MCP tool initialized")
            print(f"  Server: {mcp_tool.server_label}")
            print(f"  URL: {mcp_tool.server_url}")
            print()
            
            # Run test scenarios in a single thread
            print("=" * 70)
            print("STEP 5: Running Test Scenarios (Single Thread)")
            print("=" * 70)
            print(f"Total scenarios: {len(TEST_SCENARIOS)}")
            print()
            
            # Create a single thread for all tests
            print("Creating conversation thread...")
            thread = agents_client.threads.create()
            print(f"✓ Thread created: {thread.id}")
            print()
            
            for i, scenario in enumerate(TEST_SCENARIOS, 1):
                print(f"\n{'='*70}")
                print(f"SCENARIO {i}/{len(TEST_SCENARIOS)}")
                print(f"{'='*70}")
                print(f"Name: {scenario['name']}")
                print(f"Description: {scenario['description']}")
                print(f"Query: {scenario['query']}")
                print()
                
                # Add message to existing thread
                print(f"Adding message to thread {thread.id}...")
                message = agents_client.messages.create(
                    thread_id=thread.id,
                    role="user",
                    content=scenario["query"]
                )
                print(f"✓ Message created: {message.id}")
                
                # Create run
                print("Creating agent run...")
                run = agents_client.runs.create(
                    thread_id=thread.id,
                    agent_id=agent_id,
                    tool_resources=mcp_tool.resources
                )
                print(f"✓ Run created: {run.id}")
                print()
                
                # Wait for completion
                print("Waiting for run to complete...")
                attempt = 0
                max_attempts = 60
                tool_calls_made = []
                
                while run.status in ["queued", "in_progress", "requires_action"]:
                    time.sleep(1)
                    attempt += 1
                    run = agents_client.runs.get(thread_id=thread.id, run_id=run.id)
                    
                    if attempt % 5 == 0 or run.status == "requires_action":
                        print(f"  [{attempt}] Status: {run.status}")
                    
                    # Handle tool approvals
                    if run.status == "requires_action" and isinstance(run.required_action, SubmitToolApprovalAction):
                        tool_calls = run.required_action.submit_tool_approval.tool_calls
                        if not tool_calls:
                            print("⚠ No tool calls provided - cancelling run")
                            agents_client.runs.cancel(thread_id=thread.id, run_id=run.id)
                            break
                        
                        tool_approvals = []
                        for tool_call in tool_calls:
                            if isinstance(tool_call, RequiredMcpToolCall):
                                print(f"  ✓ MCP Tool Call Detected: {tool_call.name}")
                                print(f"    Arguments: {tool_call.arguments}")
                                tool_calls_made.append({
                                    "name": tool_call.name,
                                    "arguments": tool_call.arguments
                                })
                                tool_approvals.append(
                                    ToolApproval(
                                        tool_call_id=tool_call.id,
                                        approve=True,
                                        headers=mcp_tool.headers,
                                    )
                                )
                        
                        if tool_approvals:
                            print(f"  Submitting {len(tool_approvals)} tool approval(s)...")
                            agents_client.runs.submit_tool_outputs(
                                thread_id=thread.id,
                                run_id=run.id,
                                tool_approvals=tool_approvals
                            )
                    
                    if attempt >= max_attempts:
                        print("⚠ Timeout waiting for run to complete")
                        break
                
                print()
                print(f"Run Status: {run.status}")
                
                # Get the latest assistant response
                messages = agents_client.messages.list(
                    thread_id=thread.id,
                    order=ListSortOrder.ASCENDING
                )
                
                agent_response = None
                for msg in messages:
                    if msg.role == "assistant" and msg.text_messages:
                        agent_response = msg.text_messages[-1].text.value
                
                # Display results
                print()
                print("-" * 70)
                print("RESULTS:")
                print("-" * 70)
                
                success = run.status == "completed"
                if success:
                    print("✅ SUCCESS")
                    if tool_calls_made:
                        print(f"   Tool Calls: {len(tool_calls_made)}")
                        for tc in tool_calls_made:
                            print(f"   - {tc['name']}")
                    else:
                        print("   No tool calls (direct response)")
                    if agent_response:
                        print()
                        print("Response:")
                        print(agent_response[:500] + ("..." if len(agent_response) > 500 else ""))
                else:
                    print(f"❌ FAILED - Status: {run.status}")
                
                print("-" * 70)
                
                test_results.append({
                    "scenario": scenario["name"],
                    "success": success,
                    "response": agent_response,
                    "tool_calls": tool_calls_made
                })
                
                # Brief pause between scenarios
                if i < len(TEST_SCENARIOS):
                    print("\nPausing 2 seconds before next scenario...")
                    time.sleep(2)
            
            # Summary
            print()
            print("=" * 70)
            print("TEST SUMMARY")
            print("=" * 70)
            print()
            
            successful = sum(1 for r in test_results if r["success"])
            total = len(test_results)
            
            print(f"Total Tests: {total}")
            print(f"Passed: {successful}")
            print(f"Failed: {total - successful}")
            print()
            
            for i, result in enumerate(test_results, 1):
                status_icon = "✅" if result["success"] else "❌"
                tools_info = f" ({len(result['tool_calls'])} tool calls)" if result['tool_calls'] else " (no tools)"
                print(f"{status_icon} Scenario {i}: {result['scenario']}{tools_info}")
            
            print()
            print("=" * 70)
            
            if successful == total:
                print("🎉 ALL TESTS PASSED!")
                return 0
            else:
                print(f"⚠️  {total - successful} TEST(S) FAILED")
                return 1
            
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    finally:
        print()
        print("Test suite complete")


if __name__ == "__main__":
    sys.exit(main())
