/* 
All public gists https://gist.github.com/litknd
Copyright 2017, Kendra Little
MIT License, http://www.opensource.org/licenses/mit-license.php
*/

USE master
GO

/*******************************************************************
SETUP

WideWorldImporters is free from Microsoft:
https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0
This demo restores WideWorldImporters-Full.bak

WideWorldImporters can be restored to SQL Server 2016 and higher
*******************************************************************/

IF DB_ID('WideWorldImporters') IS NOT NULL
ALTER DATABASE WideWorldImporters SET OFFLINE WITH ROLLBACK IMMEDIATE

RESTORE DATABASE WideWorldImporters FROM DISK=
	'S:\MSSQL\Backup\WideWorldImporters-Full.bak'  /* EDIT BACKUP LOCATION IF NEEDED!*/
	WITH REPLACE
GO

ALTER DATABASE WideWorldImporters SET AUTO_UPDATE_STATISTICS_ASYNC OFF;
GO

/* Compat level 130 improves the auto-stats update algorithm. We're going to use the old one.*/
ALTER DATABASE WideWorldImporters SET COMPATIBILITY_LEVEL = 120
GO

USE WideWorldImporters;
GO

/* The new cardinality estimator fixes some of the problems we're going to see. We're going to use legacy. */
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
GO

/* Run this to create a column stat on LastEditedWhen */
SELECT COUNT(*) FROM Sales.Invoices WHERE LastEditedWhen > '2020-01-01';
GO

/* Now insert a bunch of rows -- but not enough to trigger stats update */
INSERT Sales.Invoices
    (CustomerID, BillToCustomerID, OrderID, DeliveryMethodID, ContactPersonID, AccountsPersonID, SalespersonPersonID, PackedByPersonID, InvoiceDate, CustomerPurchaseOrderNumber, IsCreditNote, CreditNoteReason, Comments, DeliveryInstructions, InternalComments, TotalDryItems, TotalChillerItems, DeliveryRun, RunPosition, ReturnedDeliveryData, LastEditedBy, LastEditedWhen)
SELECT TOP 12000
    CustomerID, BillToCustomerID, OrderID, DeliveryMethodID, ContactPersonID, AccountsPersonID, SalespersonPersonID, PackedByPersonID, InvoiceDate, CustomerPurchaseOrderNumber, IsCreditNote, CreditNoteReason, Comments, DeliveryInstructions, InternalComments, TotalDryItems, TotalChillerItems, DeliveryRun, RunPosition, ReturnedDeliveryData, LastEditedBy, '2017-04-19'
FROM Sales.Invoices;
GO


/*******************************************************************
DEMO
*******************************************************************/

DROP PROCEDURE IF EXISTS dbo.InvoicesByLastEditedWhen
GO
CREATE PROCEDURE dbo.InvoicesByLastEditedWhen
    @CutoffDate datetime2(7)
AS
    SET NOCOUNT ON;

    SELECT 
        si.InvoiceID,
        sil.InvoiceLineID,
        si.OrderID,
        si.InvoiceDate,
        si.ReturnedDeliveryData,
        sil.[Description],
        si.LastEditedWhen
    FROM Sales.Invoices AS si
    LEFT JOIN Sales.InvoiceLines as sil on 
        si.InvoiceID = sil.InvoiceID
    WHERE 
        si.LastEditedWhen >= @CutoffDate;
GO

/* The first time that it's run... */
exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-01-01';
GO

/* Then it's run for other dates... */
exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-03-01';
exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-04-01';
exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-04-30';
GO


/************************************************************ 
Step 1: Get the plan for the slow query

Since this is a procedure, we could look in sys.dm_exec_procedure_stats
I'm looking at sys.dm_exec_query_stats with part of the TSQL just in case people
    want to find queries that don't run as part of procedures
************************************************************/
SELECT
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END 
            - qs.statement_start_offset)/2) + 1) AS [query_text],
    qs.execution_count,
    qs.total_worker_time,
    qs.total_logical_reads,
    qs.total_elapsed_time,
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text (plan_handle) as st
CROSS APPLY sys.dm_exec_query_plan (plan_handle) AS qp
WHERE st.text like '%si.LastEditedWhen >= @CutoffDate;%'
    OPTION (RECOMPILE);
GO


/************************************************************ 
Step 2: Save that plan!
************************************************************/


/************************************************************ 
Step 3: Inspect the parameters
************************************************************/



/************************************************************ 
Step 4: Were row estimates close?

The easiest way to guess at this is to get an actual plan -- if it's OK
to rerun the query
************************************************************/

exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-01-01 00:00:00.0000000';
GO

/* If we can't re-run the query, we could...
    See if we could restore a backup to just after the execution plan was cached elsewhere
        Run a query there
    Run queries to count rows in the table to validate the estimates (if that's OK)
*/

/************************************************************ 
Step 5: Is the query actually slow?
************************************************************/
SET STATISTICS IO, TIME ON;
GO
exec dbo.InvoicesByLastEditedWhen @CutoffDate='2017-01-01 00:00:00.0000000';
GO
SET STATISTICS IO, TIME ON;
GO

--SQL Server Execution Times:
--   CPU time = 126 ms,  elapsed time = 163 ms.

/* 
Stats are "off" in my case, but the query still performs very quickly.
This is often the case! 
It may be that the query is slow because sometimes when it runs it's being blocked. 
Or it may be that when one plan is in cache and the query is run for different parameters, it's slow then.

I shouldn't blame the statistics in this case. The stats aren't perfect, but they created a resonable plan
    for the parameter values they were given.
*/


/* What if I get a different plan than the one that was in the cache?
    Slow in the Application, Fast in SSMS? An SQL text by Erland Sommarskog
    http://www.sommarskog.se/query-plan-mysteries.html
*/

/************************************************************ 
Step 6: Inspect your statistics (if needed)
************************************************************/
/* If using SQL Server 2008 or prior, a query that works with those versions is at
https://www.littlekendra.com/2016/12/06/when-did-sql-server-last-update-that-statistic-how-much-has-been-modified-since-and-what-columns-are-in-the-stat/
*/
SELECT 
    stat.auto_created,
    stat.name as stats_name,
    STUFF((SELECT ', ' + cols.name
        FROM sys.stats_columns AS statcols
        JOIN sys.columns AS cols ON
            statcols.column_id=cols.column_id
            AND statcols.object_id=cols.object_id
        WHERE statcols.stats_id = stat.stats_id and
            statcols.object_id=stat.object_id
        ORDER BY statcols.stats_column_id
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')  as stat_cols,
    stat.filter_definition,
    stat.is_temporary,
    stat.no_recompute,
    sp.last_updated,
    sp.modification_counter,
    sp.rows,
    sp.rows_sampled
FROM sys.stats as stat
CROSS APPLY sys.dm_db_stats_properties (stat.object_id, stat.stats_id) AS sp
JOIN sys.objects as so on 
    stat.object_id=so.object_id
JOIN sys.schemas as sc on
    so.schema_id=sc.schema_id
WHERE 
    sc.name= 'Sales'
    and so.name='Invoices'
ORDER BY 1, 2;
GO
