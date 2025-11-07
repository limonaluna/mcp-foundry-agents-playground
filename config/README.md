# Configuration Files

This folder contains deployment outputs and optional configuration files.

## Files

### Active Configuration
- **`.env`** - Environment variables (at Foundry root, not in this folder - gitignored)
- **`.env.example`** - Example environment file (at Foundry root - copy to `.env`)
- **`config.template.json`** - Legacy template configuration with placeholders (optional)
- **`config.json`** - Legacy active configuration (gitignored, optional)

### Deployment Outputs
- **`foundry-deployment-outputs.json`** - Azure AI Foundry deployment outputs
- **`mcp-sql-server-deployment-outputs.json`** - MCP SQL Server deployment outputs
- **`deployment-info.json`** - Infrastructure deployment information

## Setup

1. **Copy `.env.example` to `.env`** at the Foundry root folder (one level up):
   ```bash
   # From the Foundry root:
   cp .env.example .env
   ```

2. **Edit `.env`** with your actual values:
   ```bash
   SERVER_NAME=your-server.database.windows.net
   DATABASE_NAME=your-database
   RESOURCE_GROUP=mcp
   AZURE_LOCATION=swedencentral
   ```

3. **Run deployment** - the scripts will automatically:
   - Read configuration from `.env`
   - Create deployment output files in this folder

## Notes

- **`.env` is at the Foundry root** (not in config/ folder) to match standard conventions
- `config.json` and deployment outputs are gitignored to avoid committing secrets
- The deployment scripts automatically create JSON output files in this folder
- `config.template.json` is legacy - new deployments use `.env` exclusively
