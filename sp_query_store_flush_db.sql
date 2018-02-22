SET NOCOUNT ON;
GO

USE master;
GO

IF DB_ID('QueryStoreTest') IS NOT NULL
BEGIN
    ALTER DATABASE QueryStoreTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE QueryStoreTest;
END
GO

CREATE DATABASE QueryStoreTest;
GO

ALTER DATABASE QueryStoreTest SET QUERY_STORE = ON
GO
ALTER DATABASE QueryStoreTest SET QUERY_STORE (OPERATION_MODE = READ_WRITE)
GO

USE QueryStoreTest;
GO

CREATE TABLE dbo.Foo (i int identity not null);
GO

INSERT dbo.Foo DEFAULT VALUES 
GO 100

select i as [before_backup]
from dbo.Foo;
GO

/* If you don't run sys.sp_query_store_flush_db and you run the code sample without
waiting for the default flush interval to pass, the insert and select before the backup
won't end up in the backup */
exec sys.sp_query_store_flush_db;
GO

use master;
GO

BACKUP DATABASE QueryStoreTest to disk = 'QueryStoreTest.bak' WITH INIT;
GO


IF DB_ID('QueryStoreTest') IS NOT NULL
BEGIN
    ALTER DATABASE QueryStoreTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE QueryStoreTest;
END
GO


RESTORE DATABASE QueryStoreTest FROM DISK='QueryStoreTest.bak'
	WITH RECOVERY;
GO

use QueryStoreTest;
GO

SELECT *
FROM sys.database_query_store_options;
GO

select i as [after_restore]
from dbo.Foo;
GO

/* Read query store activity */
SELECT TOP 100
    (SELECT TOP 1 CAST(qsqt.query_sql_text AS NVARCHAR(MAX)) 
        FROM sys.query_store_query_text qsqt
        WHERE qsqt.query_text_id = MAX(qsq.query_text_id)  FOR XML PATH(''),TYPE) AS sqltext, 
    qcs.set_options as [set options],
    qsq.object_id,
    QUOTENAME(sc.name) + N'.' + QUOTENAME(so.name) as [object name],   
    SUM(qrs.count_executions) AS [# executions],
    SUM(qsq.count_compiles) AS [# compiles],
    AVG(qrs.avg_rowcount) AS [avg rowcount],
    AVG(qrs.avg_dop) AS [avg DOP],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_duration/1000000.) AS MONEY),1) AS [avg duration sec],
    AVG(qrs.avg_duration/1000000.) AS [avg duration sec n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_duration)/1000000. AS MONEY), 1) as [total duration sec],
    SUM(qrs.count_executions*qrs.avg_duration)/1000000. as [total duration sec n],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_cpu_time/1000000.) AS MONEY),1) AS [avg cpu sec],
    AVG(qrs.avg_cpu_time/1000000.) AS [avg cpu sec n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_cpu_time)/1000000. AS MONEY), 1) as [total cpu sec],
    SUM(qrs.count_executions*qrs.avg_cpu_time)/1000000. as [total cpu sec n],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_query_max_used_memory)*8./1024. AS MONEY), 1) AS [avg max used mem (MB)],
    AVG(qrs.avg_query_max_used_memory)*8./1024. AS [avg max used mem (MB) n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_query_max_used_memory)*8./1024. AS MONEY), 1) AS [total max used mem (MB)],
    SUM(qrs.count_executions*qrs.avg_query_max_used_memory)*8./1024. AS [total max used mem (MB) n],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_logical_io_reads) AS MONEY), 1) AS [avg logical reads],
    AVG(qrs.avg_logical_io_reads) AS [avg logical reads n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_logical_io_reads) AS MONEY), 1) AS [total logical reads],
    SUM(qrs.count_executions*qrs.avg_logical_io_reads) AS [total logical reads n],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_physical_io_reads) AS MONEY), 1) AS [avg physical reads],
    AVG(qrs.avg_physical_io_reads) AS [avg physical reads n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_physical_io_reads) AS MONEY), 1) AS [total physical reads],
    SUM(qrs.count_executions*qrs.avg_physical_io_reads) AS [total physical reads n],
    CONVERT(VARCHAR,CAST(AVG(qrs.avg_logical_io_writes) AS MONEY), 1) as [avg writes],
    AVG(qrs.avg_logical_io_writes) as [avg writes n],
    CONVERT(VARCHAR,CAST(SUM(qrs.count_executions*qrs.avg_logical_io_writes) AS MONEY), 1) as [total writes],
    SUM(qrs.count_executions*qrs.avg_logical_io_writes) as [total writes n],
    MIN(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as [first execution time PST],
    MAX(qrs.last_execution_time AT TIME ZONE 'Pacific Standard Time') as [last execution time PST],
    TRY_CONVERT(XML, (
        SELECT TOP 1 qsp2.query_plan 
        FROM sys.query_store_plan AS qsp2
        WHERE qsp2.query_id=qsq.query_id
        ORDER BY qsp2.plan_id DESC)) AS [most recent plan],
    qsq.query_id as [query id],
    qsq.query_hash as [query hash]
FROM sys.query_store_query AS qsq
LEFT OUTER JOIN sys.query_context_settings as qcs on
    qsq.context_settings_id=qcs.context_settings_id
LEFT OUTER JOIN sys.objects AS so on qsq.object_id = so.object_id
LEFT OUTER JOIN sys.schemas AS sc on so.schema_id = sc.schema_id
JOIN sys.query_store_plan AS qsp on qsq.query_id=qsp.query_id
JOIN sys.query_store_runtime_stats AS qrs on qsp.plan_id = qrs.plan_id
JOIN sys.query_store_runtime_stats_interval AS qsrsi 
    ON qrs.runtime_stats_interval_id=qsrsi.runtime_stats_interval_id
GROUP BY 
    qsq.query_id, qsq.query_hash, qcs.set_options, qsq.object_id, sc.name, so.name
ORDER BY 
	SUM(qrs.count_executions*qrs.avg_cpu_time) DESC
GO