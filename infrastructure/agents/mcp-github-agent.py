"""
Configure Azure AI Foundry agent for GitHub MCP server.

This script creates or updates the GitHub MCP agent using centralized configuration.
Configuration is loaded from deploy/config.json.

Reference: https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/model-context-protocol-samples?pivots=python
"""

import os
import sys
import json
from pathlib import Path
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.ai.agents.models import McpTool

# Load centralized configuration
CONFIG_DIR = Path(__file__).parent.parent.parent / "config"
CONFIG_FILE = CONFIG_DIR / "config.json"


def load_config():
    """Load centralized configuration."""
    if not CONFIG_FILE.exists():
        raise FileNotFoundError(
            f"Configuration file not found: {CONFIG_FILE}\n"
            "Please ensure config/config.json exists with proper configuration."
        )
    
    with open(CONFIG_FILE) as f:
        return json.load(f)


def find_agent_by_name(agents_client, agent_name):
    """Find an existing agent by name."""
    try:
        agents = agents_client.list()
        for agent in agents:
            if agent.name == agent_name:
                return agent.id
        return None
    except Exception as e:
        print(f"⚠ Error searching for existing agent: {e}")
        return None


def main():
    print("=" * 70)
    print("Configure GitHub MCP Agent")
    print("=" * 70)
    print()
    
    # Load configuration
    print("Loading configuration from config.json...")
    try:
        config = load_config()
        agent_config = config["agents"]["github"]
        project_config = config["project"]
        print(f"✓ Configuration loaded")
        print()
    except Exception as e:
        print(f"❌ Failed to load configuration: {e}")
        return 1
    
    print(f"Configuration:")
    print(f"  Project Endpoint: {project_config['endpoint']}")
    print(f"  Model:            {project_config['modelDeployment']}")
    print(f"  Agent Name:       {agent_config['name']}")
    print(f"  MCP Server URL:   {agent_config['mcpServer']['url']}")
    print(f"  MCP Server Label: {agent_config['mcpServer']['label']}")
    print()
    
    # Create project client
    print("Connecting to Azure AI Foundry...")
    project_client = AIProjectClient(
        endpoint=project_config["endpoint"],
        credential=DefaultAzureCredential(),
    )
    print("✓ Connected to project")
    print()
    
    try:
        with project_client:
            agents_client = project_client.agents
            
            # Check if agent already exists
            print(f"Checking for existing agent '{agent_config['name']}'...")
            existing_agent_id = find_agent_by_name(agents_client, agent_config["name"])
            
            if existing_agent_id:
                print(f"✓ Found existing agent: {existing_agent_id}")
                update = input(f"  Update existing agent? [Y/n]: ").strip().lower()
                if update == 'n':
                    print("Operation cancelled.")
                    return 0
                action = "Updating"
            else:
                print("  No existing agent found")
                action = "Creating"
            
            print()
            
            # Initialize MCP tool (following Microsoft's pattern)
            print("Initializing GitHub MCP tool...")
            mcp_tool = McpTool(
                server_label=agent_config["mcpServer"]["label"],
                server_url=agent_config["mcpServer"]["url"],
                allowed_tools=[],  # Start with empty, then add specific tools
            )
            
            # Configure allowed tools
            for tool in agent_config.get("allowedTools", []):
                mcp_tool.allow_tool(tool)
            
            print(f"✓ MCP tool initialized")
            print(f"  Server: {mcp_tool.server_label} at {mcp_tool.server_url}")
            print(f"  Allowed tools: {mcp_tool.allowed_tools}")
            print()
            
            # Create or update agent
            print(f"{action} agent '{agent_config['name']}'...")
            
            if existing_agent_id:
                # Update existing agent
                agent = agents_client.update_agent(
                    agent_id=existing_agent_id,
                    model=project_config["modelDeployment"],
                    name=agent_config["name"],
                    instructions=agent_config["instructions"],
                    tools=mcp_tool.definitions,
                )
            else:
                # Create new agent
                agent = agents_client.create_agent(
                    model=project_config["modelDeployment"],
                    name=agent_config["name"],
                    instructions=agent_config["instructions"],
                    tools=mcp_tool.definitions,
                )
            
            print(f"✓ Agent {action.lower()} successfully!")
            print()
            print(f"Agent Details:")
            print(f"  ID:           {agent.id}")
            print(f"  Name:         {agent.name}")
            print(f"  Model:        {agent.model}")
            print(f"  Created:      {agent.created_at}")
            print()
            
            print("=" * 70)
            print("Configuration Complete!")
            print("=" * 70)
            print()
            print("Next steps:")
            print(f"1. Run: python test/test-github-agent.py")
            print(f"2. The agent will look up the ID by name automatically")
            print(f"3. All configuration is centralized in deploy/config.json")
            print()
            
            return 0
            
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
