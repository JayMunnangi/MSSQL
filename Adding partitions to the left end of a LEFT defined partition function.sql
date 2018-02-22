/*************************************************************
Demo script for adding partitions to the left end of a LEFT
defined partitioned function in SQL Server which uses one filegroup 
per partition. 

Note: this is demo code only! Use at your own risk.
 
Always test changing a partition function &/or scheme carefully a
gainst a restored backup of your database and look carefully for 
data movement or any performance concerns.
*************************************************************/


use master;
GO

SET NOCOUNT ON;
GO

/***************************************************
Set up filegroups and files
Note: there's no requirement to use a filegroup per partition -
In many cases you don't need to.
This is set up to be similar to the code in a question that was asked.
***************************************************/
IF DB_ID('PartitionSplittin') IS NOT NULL
BEGIN
	ALTER DATABASE PartitionSplittin SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE PartitionSplittin;
END
GO

CREATE DATABASE PartitionSplittin;
GO

ALTER DATABASE PartitionSplittin add FILEGROUP [201611];
GO
ALTER DATABASE PartitionSplittin add FILEGROUP [201612];
GO
ALTER DATABASE PartitionSplittin add FILEGROUP [201701];
GO
ALTER DATABASE PartitionSplittin add FILEGROUP [201702];
GO
ALTER DATABASE PartitionSplittin add FILEGROUP [201703];
GO

ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201611, FILENAME = 'S:\MSSQL\Data\FG201611.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201611];
GO
ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201612, FILENAME = 'S:\MSSQL\Data\FG201612.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201612];
GO
ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201701, FILENAME = 'S:\MSSQL\Data\FG201701.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201701];
GO
ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201702, FILENAME = 'S:\MSSQL\Data\FG201702.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201702];
GO
ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201703, FILENAME = 'S:\MSSQL\Data\FG201703.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201703];
GO



/***************************************************
Create partition function, partition scheme, and a partitioned table.
Note: 
	Doing range left with a surrogate int for a date value is a little weird,
	again, reproducing a question, not making a design recommendation.
	(Date type is only 3 bytes)

	Also, if you follow along you'll notice that it's a little problematic that
	PRIMARY was used because it's not consistent with the pattern. But that's
	how life goes sometimes, and it's part of the problem. We'll fix that.
*********************************/
USE PartitionSplittin;
GO

CREATE PARTITION FUNCTION [pf_monthly_int](INT) 
	AS RANGE LEFT FOR VALUES 
	(20161100, 20161200, 20170100, 20170200, 20170300)
GO

CREATE PARTITION SCHEME [ps_monthly_int] AS PARTITION [pf_monthly_int] 
	TO ([PRIMARY], [201611], [201612], [201701], [201702], [201703])
GO

CREATE TABLE dbo.PartitionedTable (
	UniqueCol BIGINT IDENTITY,
	PartitioningCol INT NOT NULL,
	Col1 CHAR(256) DEFAULT ('Somevalue'),
	Col2 BIT DEFAULT (1),
	Col3 INT DEFAULT ('123')
) on [ps_monthly_int](PartitioningCol);
GO

CREATE UNIQUE CLUSTERED INDEX cx_PartitionedTable on dbo.PartitionedTable (PartitioningCol, UniqueCol);
GO

/***************************************************
We've got data in three partitions
***************************************************/
INSERT dbo.PartitionedTable (PartitioningCol) VALUES ('20161101')
GO 5000
INSERT dbo.PartitionedTable (PartitioningCol) VALUES ('20161201')
GO 5000
INSERT dbo.PartitionedTable (PartitioningCol) VALUES ('20170101')
GO 5000


/***************************************************
Review the setup - 
We have data in partitions 2, 3, and 4
NOTE: The Filegroup names may appear not to match with the value in the boundary point
	This is a left based partition scheme so that value is an UPPER boundary point
	(and is actually a date value that doesn't exist). 
	So the data is in the right place, it may just look weird.
We do NOT have data below the lowest boundary point
***************************************************/

/* Use the script in:  https://gist.github.com/LitKnd/1635ac3f5cf08b5f84c974ca4b5edf6a */

/***************************************************
Now the question:
We want to load historical data before 201611.
How do we do that?
Well the first thing is that we probably don't want to put data in the PRIMARY
	filegroup, because we have a practice of not doing that.
	So we want to fix the boundary point 20161100.
	It's empty, so we can remove that boundary point without data movement.

Data movement can be suuuuuuuuper slow.
Always test on your own setup very carefully before merging boundary points in production!
***************************************************/


ALTER PARTITION FUNCTION [pf_monthly_int] ()
	MERGE RANGE ( 20161100 );
GO

/* Verify that it's gone...*/
/* Use the script in:  https://gist.github.com/LitKnd/1635ac3f5cf08b5f84c974ca4b5edf6a */


/* OK, let's add that boundary point back and give it a non-primary FG */
ALTER DATABASE PartitionSplittin add FILEGROUP [201610];
GO

ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201610, FILENAME = 'S:\MSSQL\Data\FG201610.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201610];
GO

/* We have to set it NEXT USED */
ALTER PARTITION SCHEME [ps_monthly_int] NEXT USED [201610]; 
GO 

/* Then we can SPLIT */
ALTER PARTITION FUNCTION [pf_monthly_int] () SPLIT RANGE ( 20161100 );
GO

/* So what does it look like now? */
/* Use the script in:  https://gist.github.com/LitKnd/1635ac3f5cf08b5f84c974ca4b5edf6a */

/****************************************
Let's add a few more 
****************************************/

/* Sept 2016 data */
ALTER DATABASE PartitionSplittin add FILEGROUP [201609];
GO

ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201609, FILENAME = 'S:\MSSQL\Data\FG201609.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201609];
GO

ALTER PARTITION SCHEME [ps_monthly_int] NEXT USED [201609]; 
GO 

ALTER PARTITION FUNCTION [pf_monthly_int] () SPLIT RANGE ( 20161000 );
GO

/* Aug 2016 data */
ALTER DATABASE PartitionSplittin add FILEGROUP [201608];
GO

ALTER DATABASE PartitionSplittin add FILE (
	NAME = FG201608, FILENAME = 'S:\MSSQL\Data\FG201608.ndf', SIZE = 64MB, FILEGROWTH = 256MB  
) TO FILEGROUP [201608];
GO

ALTER PARTITION SCHEME [ps_monthly_int] NEXT USED [201608]; 
GO 

ALTER PARTITION FUNCTION [pf_monthly_int] () SPLIT RANGE ( 20160900 );
GO

/* Insert some data */
INSERT dbo.PartitionedTable (PartitioningCol) VALUES ('20161001')
GO 500
INSERT dbo.PartitionedTable (PartitioningCol) VALUES ('20160901')
GO 500


/* Now review */
/* Use the script in:  https://gist.github.com/LitKnd/1635ac3f5cf08b5f84c974ca4b5edf6a */