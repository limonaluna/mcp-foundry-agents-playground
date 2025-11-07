-- Verify SalesLT (AdventureWorks) sample schema exists
-- Run this AFTER granting managed identity access

USE [contoso];
GO

-- List all SalesLT tables
SELECT 
    SCHEMA_NAME(schema_id) AS SchemaName,
    name AS TableName
FROM sys.tables
WHERE SCHEMA_NAME(schema_id) = 'SalesLT'
ORDER BY name;
GO

-- Sample query to verify data exists
SELECT TOP 5
    CustomerID,
    FirstName,
    LastName,
    CompanyName,
    EmailAddress
FROM SalesLT.Customer;
GO

-- Count records in key tables
SELECT 
    'Customer' AS TableName, 
    COUNT(*) AS RecordCount 
FROM SalesLT.Customer
UNION ALL
SELECT 
    'Product', 
    COUNT(*) 
FROM SalesLT.Product
UNION ALL
SELECT 
    'SalesOrderHeader', 
    COUNT(*) 
FROM SalesLT.SalesOrderHeader;
GO
