-- Grant MCP Managed Identity access to SQL Database
-- 
-- INSTRUCTIONS:
-- 1. Replace <MANAGED_IDENTITY_NAME> below with the actual name from your deployment
-- 2. Connect to your SQL database and run this script
-- 3. Use Azure Portal Query Editor, SSMS, or Azure Data Studio
-- 4. Make sure to login with Azure AD authentication
--
-- The managed identity name is shown in the deployment output and saved in:
-- config/mcp-sql-server-deployment-outputs.json
--
-- Example: If your managed identity name is "sqlmcp-dev-mcp-abcd1234", replace all instances below

-- Create database user for the managed identity
CREATE USER [<MANAGED_IDENTITY_NAME>] FROM EXTERNAL PROVIDER;

-- Grant read permissions
ALTER ROLE db_datareader ADD MEMBER [<MANAGED_IDENTITY_NAME>];

-- Grant write permissions
ALTER ROLE db_datawriter ADD MEMBER [<MANAGED_IDENTITY_NAME>];

-- Grant DDL permissions (for creating/modifying objects)
ALTER ROLE db_ddladmin ADD MEMBER [<MANAGED_IDENTITY_NAME>];

-- Verify the user was created
SELECT 
    name AS UserName,
    type_desc AS UserType,
    authentication_type_desc AS AuthType
FROM sys.database_principals
WHERE name = '<MANAGED_IDENTITY_NAME>';
