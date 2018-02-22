/* Note: don't run this all at once. There are prompts to run some queries in another session, etc. */

WHILE @@trancount > 0
	ROLLBACK
GO

USE master;
GO

IF DB_ID('lockingtest') IS NOT NULL
BEGIN
	ALTER DATABASE lockingtest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE lockingtest;
END
GO

CREATE DATABASE lockingtest;
GO

USE lockingtest;
GO

SET NOCOUNT ON;

/********************************************************
Here we have dbo.ProductionTable and dbo.StagingTable
*********************************************************/
DROP TABLE IF EXISTS dbo.ProductionTable;
GO

CREATE TABLE dbo.ProductionTable (
	i int identity not null,
	varcharcol varchar(256) default ('old data'),
	tinyintcol tinyint default (2),
	intcol int default (20000),
	GUIDcol uniqueidentifier default (newid()),
	datetime2col datetime2(0) default ('2016-01-01')
);
GO
/* populate */
DECLARE @i INT = 1;
BEGIN TRAN
	WHILE @i < 1000
	BEGIN
		INSERT dbo.ProductionTable DEFAULT VALUES;
		SET @i=@i+1;
	END
COMMIT
GO 

DROP TABLE IF EXISTS dbo.StagingTable;
GO

CREATE TABLE dbo.StagingTable (
	i int identity not null,
	varcharcol varchar(256) default ('New data'),
	tinyintcol tinyint default (2),
	intcol int default (20000),
	GUIDcol uniqueidentifier default (newid()),
	datetime2col datetime2(0) default ('2017-01-01')
);
GO
/* populate */
DECLARE @i INT = 1;
BEGIN TRAN
	WHILE @i < 2000
	BEGIN
		INSERT dbo.StagingTable DEFAULT VALUES;
		SET @i=@i+1;
	END
COMMIT
GO 


/********************************************************
Traditional method: use rename.
Problem: what if another query has a shared schema lock on the table?
*********************************************************/


--Run in another session:
BEGIN TRAN

	SELECT top 1 i
	FROM dbo.ProductionTable WITH (HOLDLOCK)

	


--Now back in this session:

exec sp_rename 'dbo.ProductionTable', 'ProductionTableOld';
GO

--We'll be blocked. 
--We can see this by running sp_WhoIsActive in a third session

--cancel the rename, leave the select running in the other session 



/********************************************************
Alternate approach: partition switching
*********************************************************/

--Create ProductionTableOld
CREATE TABLE dbo.ProductionTableOld (
	i int identity not null,
	varcharcol varchar(256) default ('old data'),
	tinyintcol tinyint default (2),
	intcol int default (20000),
	GUIDcol uniqueidentifier default (newid()),
	datetime2col datetime2(0) default ('2016-01-01')
);
GO

BEGIN TRAN

	ALTER TABLE dbo.ProductionTable SWITCH PARTITION 1 TO dbo.ProductionTableOld PARTITION 1
		WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

	--Anyone who tries to query the table after the switch has happened and before
	--the transaction commits will be blocked: we've got a schema mod lock on the table

	ALTER TABLE dbo.StagingTable SWITCH PARTITION 1 TO dbo.ProductionTable PARTITION 1

COMMIT

--Voila, we now have only New Data
SELECT * FROM dbo.ProductionTable

--This has old data
SELECT * FROM dbo.ProductionTableOld

--This is empty
SELECT * FROM dbo.StagingTable


/********************************************************
What if we just wanna ditch the old data?
*********************************************************/

--Rerun the commands above to create and populate ProductionTable and StagingTable
--Restart the select in another session

BEGIN TRAN

	TRUNCATE TABLE dbo.ProductionTable   
	WITH (PARTITIONS (1));

	--Anyone who tries to query the table after the switch has happened and before
	--the transaction commits will be blocked: we've got a schema mod lock on the table

	ALTER TABLE dbo.StagingTable SWITCH PARTITION 1 TO dbo.ProductionTable PARTITION 1

COMMIT

--Whoops, this has a problem. TRUNCATE TABLE doesn't have WAIT_AT_LOW_PRIORITY and its glorious options.
--If you wanna ditch the data and be able to manage the blocking situation better, you gotta
--switch out to another table with WAIT_AT_LOW_PRIORITY and your preferred options, then truncate there.