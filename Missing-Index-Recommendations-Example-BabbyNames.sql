/* Sample code that explores index recommendations in BabbyNames */

USE BabbyNames;
GO

SET NOCOUNT ON;
GO

SELECT
    ref.FirstName,
    agg.NameCount
FROM agg.FirstNameByYear as agg
JOIN ref.FirstName as ref on 
    agg.FirstNameId=ref.FirstNameId
WHERE 
    Gender='F'
    and ref.FirstName = 'Calliope';
GO 10

SELECT TOP 100
    ref.FirstName,
    agg.NameCount
FROM agg.FirstNameByYear as agg
JOIN ref.FirstName as ref on 
    agg.FirstNameId=ref.FirstNameId
WHERE 
    Gender = 'M'
ORDER BY NameCount DESC;
GO 20

/* Missing index requests for this database */
SELECT 
    d.statement as table_name,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.avg_total_user_cost as avg_est_plan_cost,
    s.avg_user_impact as avg_est_cost_reduction,
    s.user_scans + s.user_seeks as times_requested
FROM sys.dm_db_missing_index_groups AS g
JOIN sys.dm_db_missing_index_group_stats as s on
    g.index_group_handle=s.group_handle
JOIN sys.dm_db_missing_index_details as d on
    g.index_handle=d.index_handle
JOIN sys.databases as db on 
    d.database_id=db.database_id
WHERE db.database_id=DB_ID();
GO


/* Which indexes would be great for each query? */
--KEY (Gender, FirstNameId) INCLUDE NameCount
--KEY (Gender, NameCount) INCLUDE FirstNameId

/* Compromise index if the TOP query is slightly more important.
Great for the TOP query that runs 20 times, good enough for the other query*/
CREATE INDEX ix_iamapersonnotamachine on agg.FirstNameByYear
    (Gender, NameCount) INCLUDE (FirstNameId);
GO

CREATE INDEX ix_FirstName_FirstName_INCLUDES on ref.FirstName
    (FirstName) INCLUDE (FirstNameId);
GO