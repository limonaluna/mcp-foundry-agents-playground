# Local Development

This folder contains files for local development and testing.

## Files

- **docker-compose.yml** - Docker Compose configuration for running the MCP server locally

## Quick Start

### Using Docker Compose

1. **Set up environment variables:**
   ```bash
   cp ../config/.env.example ../.env
   # Edit ../.env with your values
   ```

2. **Run the server:**
   ```bash
   docker-compose up -d
   ```

3. **View logs:**
   ```bash
   docker-compose logs -f
   ```

4. **Stop the server:**
   ```bash
   docker-compose down
   ```

### Using Docker directly

1. **Build from app folder:**
   ```bash
   cd ../app
   docker build -t mssql-mcp-foundry .
   ```

2. **Run:**
   ```bash
   docker run -p 3000:3000 --env-file ../.env mssql-mcp-foundry
   ```

## Testing Endpoints

- Health: http://localhost:3000/health
- Info: http://localhost:3000/info
- SSE: http://localhost:3000/sse (requires API key header)

## Notes

- Local development uses `.env` file in the Foundry root
- Production deployment uses Azure Key Vault for secrets
- For production deployment, use `infrastructure/mcp-sql-server/deploy.ps1`
