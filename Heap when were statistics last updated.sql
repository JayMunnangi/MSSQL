/*****************************************************************************
MIT License, http://www.opensource.org/licenses/mit-license.php
Contact: help@sqlworkbooks.com
Copyright (c) 2018 SQL Workbooks LLC
Permission is hereby granted, free of charge, to any person 
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without 
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom 
the Software is furnished to do so, subject to the following 
conditions:
The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR 
OTHER DEALINGS IN THE SOFTWARE.
*****************************************************************************/


SET NOCOUNT ON;
GO

USE master;
GO

IF DB_ID('Heaps') IS NOT NULL
BEGIN
    ALTER DATABASE Heaps SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE Heaps;
END
GO

CREATE DATABASE Heaps;
GO

use Heaps;
GO

CREATE TABLE dbo.Test (
    Id BIGINT,
    SecondInt BIGINT,
    Extra INT
);
GO

--This query adapted from pattern attributed 
--to Itzik Ben-Gan in https://sqlperformance.com/2013/01/t-sql-queries/generate-a-set-1
--Generates 1 million rows
WITH cte1(num) AS
(
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL 
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL 
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1), 
cte2(num) AS (SELECT 1 FROM cte1 CROSS JOIN cte1 AS b),
cte3(num) AS (SELECT 1 FROM cte2 CROSS JOIN cte2 AS b),
cte4(num) AS (SELECT 1 FROM cte3 CROSS JOIN cte3 AS b)
INSERT  dbo.Test (Id, SecondInt, Extra)
SELECT TOP (1000000)
	ROW_NUMBER() OVER (ORDER BY (SELECT num)) as Id, 
    100 * ROW_NUMBER() OVER (ORDER BY (SELECT num)) as SecondInt, 
    555 as Extra
FROM cte4;
GO

/* Review statistic creation settings.
If model db hasn't been changed, auto create and autop update stats should be on, 
async is off by default */
select is_auto_create_stats_on, is_auto_update_stats_on, is_auto_update_stats_async_on
from sys.databases
where name='Heaps';
GO

/* This will have a statistic auto-created with the index */
CREATE INDEX ix_Test_SecondInt on dbo.Test (SecondInt);
GO

/* Running this query will automatically create a column statistic
on Extra */
SELECT COUNT(*)
FROM dbo.Test
WHERE Extra = 'Extra';
GO

/* A very simple query: what stats are on the table? */
SELECT stat.*
FROM sys.stats as stat
join sys.objects as so on stat.object_id=so.object_id
join sys.schemas as sc on so.schema_id = sc.schema_id
WHERE so.name='Test'
    and sc.name='dbo';
GO


/* More details: what columns are in the stats, when were they last updated */
SELECT 
    stat.auto_created,
    stat.name as stats_name,
    sp.last_updated,
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
    sc.name= 'dbo'
    and so.name='Test'
ORDER BY 1, 2;
GO