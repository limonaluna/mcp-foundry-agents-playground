-- Grant Managed Identity access to database
-- Run this as an Azure AD admin user

USE [contoso];
GO

-- Create user for managed identity
CREATE USER [mssql-mcp-id-7xlf5mx5xvxjm] FROM EXTERNAL PROVIDER;
GO

-- Grant database roles
ALTER ROLE db_datareader ADD MEMBER [mssql-mcp-id-7xlf5mx5xvxjm];
ALTER ROLE db_datawriter ADD MEMBER [mssql-mcp-id-7xlf5mx5xvxjm];
ALTER ROLE db_ddladmin ADD MEMBER [mssql-mcp-id-7xlf5mx5xvxjm];
GO

-- Verify permissions
SELECT 
    dp.name AS UserName,
    dp.type_desc AS UserType,
    r.name AS RoleName
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
LEFT JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
WHERE dp.name = 'mssql-mcp-id-7xlf5mx5xvxjm'
ORDER BY dp.name, r.name;
GO
