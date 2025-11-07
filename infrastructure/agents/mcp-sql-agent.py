"""
Configure Azure AI Foundry agent for MSSQL MCP server.

This script creates or updates the SQL MCP agent using centralized configuration.
Configuration is loaded from config/config.json or config/*.json files.
API key is retrieved from Azure Key Vault.
"""

import os
import sys
import json
from pathlib import Path
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.ai.agents.models import McpTool

# Load centralized configuration from config folder
CONFIG_DIR = Path(__file__).parent.parent.parent / "config"


def load_config():
    """Load centralized configuration from config/ folder."""
    # Try config.json first
    config_file = CONFIG_DIR / "config.json"
    if config_file.exists():
        with open(config_file) as f:
            return json.load(f)
    
    # Fall back to deployment outputs
    deployment_files = [
        CONFIG_DIR / "mcp-sql-server-deployment-outputs.json",
        CONFIG_DIR / "foundry-deployment-outputs.json"
    ]
    
    config = {}
    for file in deployment_files:
        if file.exists():
            with open(file) as f:
                data = json.load(f)
                # Merge into config
                if "infrastructure" in data or "mcp" in data:
                    config.setdefault("infrastructure", {}).update(data)
                else:
                    config.update(data)
    
    if not config:
        raise FileNotFoundError(
            f"No configuration found in {CONFIG_DIR}\n"
            f"Please ensure config/config.json or deployment output files exist."
        )
    
    return config


def get_mcp_api_key_from_keyvault(key_vault_name, secret_name="mcp-api-key"):
    """
    Get API key for MCP server from Azure Key Vault.
    
    Args:
        key_vault_name: Name of the Azure Key Vault
        secret_name: Name of the secret containing the API key
        
    Returns:
        API key string
    """
    try:
        credential = DefaultAzureCredential()
        key_vault_uri = f"https://{key_vault_name}.vault.azure.net"
        secret_client = SecretClient(vault_url=key_vault_uri, credential=credential)
        
        print(f"Retrieving API key from Key Vault: {key_vault_name}")
        secret = secret_client.get_secret(secret_name)
        print(f"✓ API key retrieved from Key Vault secret: {secret_name}")
        return secret.value
    except Exception as e:
        raise RuntimeError(
            f"Failed to retrieve API key from Key Vault '{key_vault_name}':\n{e}\n\n"
            f"Please ensure:\n"
            f"1. You are authenticated to Azure (run 'az login')\n"
            f"2. You have access to the Key Vault '{key_vault_name}'\n"
            f"3. The secret '{secret_name}' exists in the Key Vault"
        )


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
    print("Configure SQL MCP Agent")
    print("=" * 70)
    print()
    
    # Load configuration
    print("Loading configuration from config.json...")
    try:
        config = load_config()
        agent_config = config["agents"]["sql"]
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
    
    # Get API key if required
    api_key = None
    if agent_config["mcpServer"]["authType"] == "apiKey":
        print("Loading MCP API key from Azure Key Vault...")
        try:
            infra_config = config.get("infrastructure", {})
            mcp_config = infra_config.get("mcp", {})
            key_vault_config = mcp_config.get("keyVault", {})
            key_vault_name = key_vault_config.get("name")
            secret_name = key_vault_config.get("apiKeySecretName", "mcp-api-key")
            
            if not key_vault_name:
                raise ValueError(
                    "Key Vault name not found in config.json.\n"
                    "Please update infrastructure.mcp.keyVault.name in config.json"
                )
            
            api_key = get_mcp_api_key_from_keyvault(key_vault_name, secret_name)
        except Exception as e:
            print(f"❌ {e}")
            return 1
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
            
            # Initialize MCP tool
            print("Initializing MCP tool...")
            mcp_tool = McpTool(
                server_label=agent_config["mcpServer"]["label"],
                server_url=agent_config["mcpServer"]["url"],
                allowed_tools=agent_config.get("allowedTools", []),
            )
            
            # Set API key header if required
            if api_key:
                mcp_tool.update_headers("X-API-Key", api_key)
            
            print(f"✓ MCP tool initialized")
            print(f"  Server: {mcp_tool.server_label} at {mcp_tool.server_url}")
            print(f"  Allowed tools: {mcp_tool.allowed_tools if mcp_tool.allowed_tools else 'All'}")
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
            print(f"1. Run: python test/test-sql-agent.py")
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
