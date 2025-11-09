#!/usr/bin/env node

import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import sql from 'mssql';
import { DefaultAzureCredential, ManagedIdentityCredential, ClientSecretCredential } from '@azure/identity';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  isInitializeRequest,
} from '@modelcontextprotocol/sdk/types.js';
import { randomUUID } from 'crypto';
import { apiKeyAuth, rateLimiter } from './middleware/auth-simple.js';

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;
const AUTH_MODE = process.env.AUTH_MODE || 'apikey';

// Middleware
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
  credentials: true
}));
app.use(express.json());

// Health check endpoint (public - no auth required)
app.get('/health', (req: Request, res: Response) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'mssql-mcp-server-foundry',
    version: '1.0.0',
    protocol: 'MCP over SSE'
  });
});

// API Key Authentication
console.log('API Key authentication enabled');

if (!process.env.API_KEY) {
  console.error('ERROR: API_KEY environment variable is required');
  process.exit(1);
}

app.use(apiKeyAuth);

// Optional: Rate limiting
if (process.env.ENABLE_RATE_LIMITING === 'true') {
  console.log('Rate limiting enabled');
  app.use(rateLimiter);
}

// Global SQL connection
let globalSqlPool: sql.ConnectionPool | null = null;
let globalAccessToken: string | null = null;
let globalTokenExpiresOn: Date | null = null;

// User session tracking for SSE connections
interface SessionUser {
  userId: string;
  displayName?: string;
  email?: string;
  sessionId: string;
}

const sseUserSessions = new Map<string, SessionUser>();

function getSessionUser(sessionId?: string): SessionUser {
  if (!sessionId) {
    return { userId: 'system', sessionId: 'none' };
  }
  return sseUserSessions.get(sessionId) || { userId: 'anonymous', sessionId };
}

// SQL Configuration
async function createSqlConfig(): Promise<{ config: sql.config, token: string, expiresOn: Date }> {
  // Choose SQL authentication method based on environment
  let credential;
  const sqlAuthMode = process.env.SQL_AUTH_MODE || 'auto';
  
  switch (sqlAuthMode) {
    case 'managed-identity':
      // Azure Managed Identity (Container Apps, AKS, etc.)
      console.log('🔐 Using Managed Identity for SQL authentication');
      
      // Use specific client ID if provided (for user-assigned managed identity)
      const clientId = process.env.AZURE_CLIENT_ID_SQL;
      if (clientId) {
        console.log(`🆔 Using User-Assigned Managed Identity: ${clientId.substring(0, 8)}...`);
        credential = new ManagedIdentityCredential({ clientId });
      } else {
        console.log('🆔 Using System-Assigned Managed Identity');
        credential = new ManagedIdentityCredential();
      }
      break;
      
    case 'service-principal':
      // Service Principal with client secret (for development/testing)
      console.log('🔐 Using Service Principal for SQL authentication');
      const { ClientSecretCredential } = await import('@azure/identity');
      credential = new ClientSecretCredential(
        process.env.SQL_TENANT_ID || process.env.AZURE_TENANT_ID!,
        process.env.SQL_CLIENT_ID || process.env.AZURE_CLIENT_ID!,
        process.env.SQL_CLIENT_SECRET!
      );
      break;
      
    case 'auto':
    default:
      // Auto-detect: Use managed identity in Azure, Azure CLI locally
      console.log('🔐 Auto-detecting SQL authentication method');
      
      // For SQL authentication, we want to use Azure CLI or Managed Identity
      // Not the HTTP OAuth credentials that might be set
      // So we temporarily clear those env vars if in OAuth mode
      const savedClientId = process.env.AZURE_CLIENT_ID;
      const savedClientSecret = process.env.AZURE_CLIENT_SECRET;
      const savedTenantId = process.env.AZURE_TENANT_ID;
      
      if (AUTH_MODE === 'oauth') {
        // Temporarily remove HTTP OAuth env vars to prevent SQL from using them
        delete process.env.AZURE_CLIENT_ID;
        delete process.env.AZURE_CLIENT_SECRET;
        delete process.env.AZURE_TENANT_ID;
      }
      
      try {
        // DefaultAzureCredential will try:
        // 1. Managed Identity (works in Azure containers)
        // 2. Azure CLI (works locally after 'az login')
        // 3. Other methods...
        credential = new DefaultAzureCredential();
      } finally {
        // Restore HTTP OAuth env vars
        if (AUTH_MODE === 'oauth') {
          if (savedClientId) process.env.AZURE_CLIENT_ID = savedClientId;
          if (savedClientSecret) process.env.AZURE_CLIENT_SECRET = savedClientSecret;
          if (savedTenantId) process.env.AZURE_TENANT_ID = savedTenantId;
        }
      }
      break;
  }
  
  const accessToken = await credential.getToken('https://database.windows.net/.default');

  return {
    config: {
      server: process.env.SERVER_NAME!,
      database: process.env.DATABASE_NAME!,
      options: {
        encrypt: true,
        trustServerCertificate: process.env.TRUST_SERVER_CERTIFICATE?.toLowerCase() === 'true'
      },
      authentication: {
        type: 'azure-active-directory-access-token',
        options: {
          token: accessToken?.token!,
        },
      },
      connectionTimeout: (process.env.CONNECTION_TIMEOUT ? parseInt(process.env.CONNECTION_TIMEOUT, 10) : 30) * 1000,
    },
    token: accessToken?.token!,
    expiresOn: accessToken?.expiresOnTimestamp ? new Date(accessToken.expiresOnTimestamp) : new Date(Date.now() + 30 * 60 * 1000)
  };
}

async function ensureSqlConnection() {
  if (
    globalSqlPool &&
    globalSqlPool.connected &&
    globalAccessToken &&
    globalTokenExpiresOn &&
    globalTokenExpiresOn > new Date(Date.now() + 2 * 60 * 1000)
  ) {
    return;
  }

  const { config, token, expiresOn } = await createSqlConfig();
  globalAccessToken = token;
  globalTokenExpiresOn = expiresOn;

  if (globalSqlPool && globalSqlPool.connected) {
    await globalSqlPool.close();
  }

  globalSqlPool = await sql.connect(config);
  console.log('✅ Connected to SQL Database');
}

// MCP Server Setup
const mcpServer = new Server(
  {
    name: 'mssql-mcp-server-foundry',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Tool Definitions
const tools = [
  {
    name: 'read_data',
    description: 'Execute SELECT queries on the database',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'SQL SELECT query to execute'
        }
      },
      required: ['query']
    }
  },
  {
    name: 'list_table',
    description: 'List all tables in the database',
    inputSchema: {
      type: 'object',
      properties: {
        parameters: {
          type: 'array',
          description: 'Optional schema names to filter',
          items: { type: 'string' }
        }
      }
    }
  },
  {
    name: 'describe_table',
    description: 'Get schema information for a specific table',
    inputSchema: {
      type: 'object',
      properties: {
        tableName: {
          type: 'string',
          description: 'Name of the table to describe'
        }
      },
      required: ['tableName']
    }
  }
];

// MCP Request Handlers
mcpServer.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools
}));

mcpServer.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  
  // Get user context from session
  // Note: MCP SDK doesn't expose sessionId directly in request
  // We'll need to track it via the transport connection
  // For now, we'll use the first active session (single-session assumption)
  const sessionId = Array.from(sseUserSessions.keys())[0];
  const user = getSessionUser(sessionId);
  
  try {
    await ensureSqlConnection();
    let result;

    switch (name) {
      case 'read_data':
        result = await executeReadData(args, user);
        break;
      case 'list_table':
        result = await executeListTable(args, user);
        break;
      case 'describe_table':
        result = await executeDescribeTable(args, user);
        break;
      default:
        return {
          content: [{ type: 'text', text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }

    return {
      content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
    };
  } catch (error) {
    return {
      content: [{ type: 'text', text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}` }],
      isError: true,
    };
  }
});

// Tool Implementations
interface UserInfo {
  userId: string;
  displayName?: string;
  email?: string;
}

async function executeReadData(args: any, user?: UserInfo) {
  const { query } = args;
  
  if (!query || typeof query !== 'string') {
    throw new Error('Query is required and must be a string');
  }

  if (!query.trim().toUpperCase().startsWith('SELECT')) {
    throw new Error('Only SELECT queries are allowed');
  }

  const request = new sql.Request();
  const result = await request.query(query);
  
  return {
    success: true,
    message: `Retrieved ${result.recordset.length} record(s)`,
    data: result.recordset,
    recordCount: result.recordset.length,
    executedAt: new Date().toISOString(),
    executedBy: user?.displayName || user?.userId || 'unknown'
  };
}

async function executeListTable(args: any, user?: UserInfo) {
  const { parameters } = args || {};
  
  const request = new sql.Request();
  const schemaFilter = parameters && parameters.length > 0 
    ? `AND TABLE_SCHEMA IN (${parameters.map((p: string) => `'${p}'`).join(", ")})` 
    : "";
  
  const query = `SELECT TABLE_SCHEMA + '.' + TABLE_NAME as [table] FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ${schemaFilter} ORDER BY TABLE_SCHEMA, TABLE_NAME`;
  
  const result = await request.query(query);
  
  return {
    success: true,
    message: 'List tables executed successfully',
    tables: result.recordset,
    tableCount: result.recordset.length,
    executedAt: new Date().toISOString(),
    executedBy: user?.displayName || user?.userId || 'unknown'
  };
}

async function executeDescribeTable(args: any, user?: UserInfo) {
  const { tableName } = args;
  
  if (!tableName || typeof tableName !== 'string') {
    throw new Error('tableName is required and must be a string');
  }

  const request = new sql.Request();
  const query = `SELECT COLUMN_NAME as name, DATA_TYPE as type FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @tableName`;
  request.input('tableName', sql.NVarChar, tableName);
  
  const result = await request.query(query);
  
  return {
    success: true,
    tableName: tableName,
    columns: result.recordset,
    columnCount: result.recordset.length,
    executedAt: new Date().toISOString(),
    executedBy: user?.displayName || user?.userId || 'unknown'
  };
}

// Root endpoint - Landing page
app.get('/', (req: Request, res: Response) => {
  const baseUrl = `${req.protocol}://${req.get('host')}`;
  
  res.type('html').send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MSSQL MCP Server - Azure AI Foundry</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      max-width: 900px;
      margin: 40px auto;
      background: white;
      border-radius: 12px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      overflow: hidden;
    }
    .header {
      background: linear-gradient(135deg, #0078d4 0%, #00bcf2 100%);
      color: white;
      padding: 40px;
      text-align: center;
    }
    .header h1 {
      font-size: 2.5em;
      margin-bottom: 10px;
      font-weight: 600;
    }
    .header p {
      font-size: 1.2em;
      opacity: 0.95;
    }
    .content {
      padding: 40px;
    }
    .section {
      margin-bottom: 40px;
    }
    .section h2 {
      color: #0078d4;
      font-size: 1.8em;
      margin-bottom: 15px;
      border-bottom: 2px solid #f0f0f0;
      padding-bottom: 10px;
    }
    .badge {
      display: inline-block;
      background: #00bcf2;
      color: white;
      padding: 6px 12px;
      border-radius: 20px;
      font-size: 0.85em;
      font-weight: 600;
      margin: 5px 5px 5px 0;
    }
    .badge.success { background: #107c10; }
    .badge.warning { background: #ff8c00; }
    .badge.info { background: #0078d4; }
    .endpoint {
      background: #f8f9fa;
      border-left: 4px solid #0078d4;
      padding: 15px 20px;
      margin: 10px 0;
      border-radius: 4px;
      font-family: 'Courier New', monospace;
    }
    .endpoint code {
      color: #d73a49;
      font-weight: 600;
    }
    .endpoint .method {
      display: inline-block;
      background: #0078d4;
      color: white;
      padding: 4px 10px;
      border-radius: 4px;
      font-weight: 600;
      font-size: 0.85em;
      margin-right: 10px;
    }
    .endpoint .method.post { background: #28a745; }
    .feature-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-top: 20px;
    }
    .feature-card {
      background: #f8f9fa;
      padding: 20px;
      border-radius: 8px;
      border-left: 4px solid #00bcf2;
    }
    .feature-card h3 {
      color: #0078d4;
      margin-bottom: 10px;
      font-size: 1.2em;
    }
    .feature-card p {
      color: #666;
      font-size: 0.95em;
    }
    .cta-box {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 30px;
      border-radius: 8px;
      text-align: center;
      margin-top: 30px;
    }
    .cta-box h3 {
      font-size: 1.5em;
      margin-bottom: 15px;
    }
    .cta-box a {
      display: inline-block;
      background: white;
      color: #667eea;
      padding: 12px 30px;
      border-radius: 6px;
      text-decoration: none;
      font-weight: 600;
      margin-top: 15px;
      transition: transform 0.2s;
    }
    .cta-box a:hover {
      transform: translateY(-2px);
    }
    .footer {
      background: #f8f9fa;
      padding: 20px;
      text-align: center;
      color: #666;
      font-size: 0.9em;
    }
    .status-indicator {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: #107c10;
      margin-right: 8px;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚀 MSSQL MCP Server</h1>
      <p>Model Context Protocol Server for Azure SQL Database</p>
      <div style="margin-top: 20px;">
        <span class="badge success"><span class="status-indicator"></span>Service Running</span>
        <span class="badge info">${AUTH_MODE === 'oauth' ? 'OAuth 2.0' : 'API Key'} Authentication</span>
        <span class="badge warning">Azure AI Foundry Ready</span>
      </div>
    </div>

    <div class="content">
      <div class="section">
        <h2>📡 Available Endpoints</h2>
        
        <div class="endpoint">
          <span class="method">GET</span>
          <code>${baseUrl}/health</code>
          <p style="margin-top: 8px; color: #666;">Health check endpoint - returns service status</p>
        </div>

        <div class="endpoint">
          <span class="method">GET</span>
          <code>${baseUrl}/sse</code>
          <p style="margin-top: 8px; color: #666;">MCP Server-Sent Events endpoint (requires ${AUTH_MODE === 'oauth' ? 'OAuth' : 'API key'} authentication)</p>
        </div>

        <div class="endpoint">
          <span class="method post">POST</span>
          <code>${baseUrl}/message</code>
          <p style="margin-top: 8px; color: #666;">MCP message endpoint (requires ${AUTH_MODE === 'oauth' ? 'OAuth' : 'API key'} authentication)</p>
        </div>
      </div>

      <div class="section">
        <h2>🛠️ MCP Tools Available</h2>
        <p style="margin-bottom: 20px; color: #666;">
          This server provides the following tools for SQL operations through the Model Context Protocol:
        </p>
        
        <div class="feature-grid">
          <div class="feature-card">
            <h3>🔌 Connection</h3>
            <p>mssql_connect, mssql_disconnect, mssql_list_servers</p>
          </div>
          <div class="feature-card">
            <h3>🗄️ Database</h3>
            <p>mssql_list_databases, mssql_change_database</p>
          </div>
          <div class="feature-card">
            <h3>📊 Schema</h3>
            <p>mssql_list_tables, mssql_list_views, mssql_list_schemas, mssql_show_schema</p>
          </div>
          <div class="feature-card">
            <h3>⚡ Query</h3>
            <p>mssql_run_query, mssql_list_functions</p>
          </div>
        </div>
      </div>

      <div class="section">
        <h2>🔐 Authentication</h2>
        <p style="color: #666; margin-bottom: 15px;">
          This server uses <strong>${AUTH_MODE === 'oauth' ? 'OAuth 2.0 authentication with Azure Entra ID' : 'API key authentication'}. 
          Azure AI Foundry handles authentication automatically.
        </p>
        <div style="background: #f8f9fa; padding: 15px; border-radius: 6px; border-left: 4px solid #ff8c00;">
          <strong>⚠️ Note:</strong> Direct browser access to MCP endpoints will fail without proper ${AUTH_MODE === 'oauth' ? 'OAuth tokens' : 'API key headers'}. 
          Use this server through Azure AI Foundry or an MCP-compatible client.
        </div>
      </div>

      <div class="cta-box">
        <h3>🎯 Ready to Use with Azure AI Foundry</h3>
        <p style="opacity: 0.95;">
          Register this MCP server in your Azure AI Foundry project to start using SQL database capabilities in your AI workflows.
        </p>
        <a href="https://ai.azure.com" target="_blank">Open Azure AI Foundry →</a>
      </div>
    </div>

    <div class="footer">
      <p>
        <strong>MSSQL MCP Server for Azure AI Foundry</strong> v1.0.0
        <br>
        Powered by Model Context Protocol • Secured by Azure Entra ID
      </p>
    </div>
  </div>
</body>
</html>
  `);
});

// Store active transports by session ID
const transports = new Map<string, SSEServerTransport>();
const streamableTransports: Record<string, StreamableHTTPServerTransport> = {};

// SSE endpoint for MCP - GET to establish connection
app.get('/sse', async (req: Request, res: Response) => {
  console.log('📡 New SSE connection established (GET)');
  
  const transport = new SSEServerTransport('/sse', res);
  
  // Extract user context from API key auth
  const apiKeyContext = (req as any).userContext;
  
  if (apiKeyContext) {
    sseUserSessions.set(transport.sessionId, {
      userId: apiKeyContext.userId || 'api-key-user',
      displayName: apiKeyContext.displayName || apiKeyContext.userId || 'API Key User',
      sessionId: transport.sessionId
    });
    console.log(`API Key user: ${apiKeyContext.userId || 'api-key-user'}`);
  } else {
    sseUserSessions.set(transport.sessionId, {
      userId: 'anonymous',
      sessionId: transport.sessionId
    });
    console.log('Warning: Anonymous session (no auth)');
  }
  
  // Store the transport by its session ID
  transports.set(transport.sessionId, transport);
  
  // Clean up on close
  transport.onclose = () => {
    console.log('📡 SSE connection closed');
    transports.delete(transport.sessionId);
    sseUserSessions.delete(transport.sessionId);
  };
  
  // Connect to MCP server
  await mcpServer.connect(transport);
  
  // Start the SSE stream
  await transport.start();
});

// POST endpoint for MCP messages
app.post('/sse', async (req: Request, res: Response) => {
  console.log('📨 Received MCP POST message');
  
  // Get session ID from header or query param
  const sessionId = (req.headers['x-mcp-session-id'] as string) || req.query.sessionId as string;
  
  if (!sessionId) {
    res.status(400).json({ error: 'Missing session ID' });
    return;
  }
  
  const transport = transports.get(sessionId);
  if (!transport) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }
  
  // Handle the POST message
  await transport.handlePostMessage(req as any, res as any, req.body);
});

//=============================================================================
// STREAMABLE HTTP TRANSPORT (for Azure AI Foundry)
//=============================================================================

// Handle all MCP Streamable HTTP requests (GET, POST, DELETE) on a single endpoint
app.all('/mcp', async (req: Request, res: Response) => {
  console.log(`📡 Received ${req.method} request to /mcp`);

  try {
    // Check for existing session ID
    const sessionId = req.headers['mcp-session-id'] as string | undefined;
    let transport: StreamableHTTPServerTransport;

    if (sessionId && streamableTransports[sessionId]) {
      // Reuse existing transport
      transport = streamableTransports[sessionId];
    } else if (!sessionId && req.method === 'POST' && isInitializeRequest(req.body)) {
      // New initialization request - create new transport
      transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: () => randomUUID(),
        onsessioninitialized: (sessionId: string) => {
          console.log(`StreamableHTTP session initialized: ${sessionId}`);
          streamableTransports[sessionId] = transport;
          
          // Extract user context from API key auth
          const apiKeyContext = (req as any).userContext;
          
          if (apiKeyContext) {
            sseUserSessions.set(sessionId, {
              userId: apiKeyContext.userId || 'api-key-user',
              displayName: apiKeyContext.displayName || apiKeyContext.userId || 'API Key User',
              sessionId
            });
            console.log(`API Key user: ${apiKeyContext.userId || 'api-key-user'}`);
          } else {
            sseUserSessions.set(sessionId, {
              userId: 'anonymous',
              sessionId
            });
            console.log('Warning: Anonymous session (no auth)');
          }
        },
        onsessionclosed: (sessionId: string) => {
          console.log(`🔒 StreamableHTTP session closed: ${sessionId}`);
          delete streamableTransports[sessionId];
          sseUserSessions.delete(sessionId);
        }
      });

      // Set up onclose handler to clean up transport
      transport.onclose = () => {
        const sid = transport.sessionId;
        if (sid && streamableTransports[sid]) {
          console.log(`Transport closed for session ${sid}`);
          delete streamableTransports[sid];
          sseUserSessions.delete(sid);
        }
      };

      // Connect the transport to the MCP server
      await mcpServer.connect(transport);
    } else {
      // Missing session ID or invalid request
      res.status(400).json({
        jsonrpc: '2.0',
        error: {
          code: -32000,
          message: sessionId 
            ? 'Session not found or transport type mismatch' 
            : 'Missing session ID for non-initialization request'
        },
        id: null
      });
      return;
    }

    // Handle the request with the transport
    await transport.handleRequest(req as any, res as any, req.body);
  } catch (error) {
    console.error('❌ Error handling /mcp request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: {
          code: -32000,
          message: `Server error: ${error instanceof Error ? error.message : 'Unknown error'}`
        },
        id: null
      });
    }
  }
});

//=============================================================================
// SERVER STARTUP
//=============================================================================

// Start server
async function startServer() {
  try {
    await ensureSqlConnection();
    
    app.listen(PORT, () => {
      console.log('=================================');
      console.log('🚀 MSSQL MCP Server (Foundry)');
      console.log('=================================');
      console.log(`Server running on port ${PORT}`);
      console.log(`Auth Mode: ${AUTH_MODE}`);
      console.log(`\nEndpoints:`);
      console.log(`  GET  http://localhost:${PORT}/health`);
      console.log(`  GET  http://localhost:${PORT}/sse (MCP SSE - Legacy)`);
      console.log(`  POST http://localhost:${PORT}/sse (MCP SSE Messages)`);
      console.log(`  ALL  http://localhost:${PORT}/mcp (MCP StreamableHTTP - Azure AI Foundry)`);
      console.log('=================================');
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing server...');
  if (globalSqlPool) {
    await globalSqlPool.close();
  }
  process.exit(0);
});

startServer();
