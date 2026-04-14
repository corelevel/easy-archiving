# Easy Archiving

Easy-Archiving is a PowerShell-based framework for incremental data archiving and purging between SQL Server databases. It is designed for large tables and supports batching, resumability, schema synchronization, and safe data movement.

## Key Features
* High efficient incremental archiving and/or purging using primary key ranges
* Batch-based processing
* Resume support for interrupted runs
* Automatic schema creation on destination
* Bulk copy for high performance
* Foreign key disable/enable support during purge (use carefully)
* Detailed logging

## Important limitation
* Supports PowerShell 7.0+
* The easy-archiving database must be located on the same SQL Server instance as the source database
* The script does NOT copy:
    * timestamp/rowversion columns
    * Computed columns
    * Indexes except index used by primary key or clustered index
* Missing columns in destination:
    * Automatically added
    * Always created as NULLABLE
* Warnings are logged if differences are detected between columns in source and destination:
    * Collation
    * Nullability
    * Computed attribute

# Overview
Each archive job operates on a Table Group, which defines:
* Source database
* Destination database
* List of tables to process
* Archiving and purge settings
* Additional connection string options like ApplicationIntent, Connect Timeout, user name, password, etc

## Database Objects
# Table Group
Defines connection and behavior:
| Column          | Description                               |
| --------------- | ----------------------------------------- |
| TableGroupId    | unique identifier                         |
| Name            | group name                                |
| SrcServerName   | source SQL Server name                    |
| SrcDatabaseName | source database name                      |
| SrcConnOptions  | source connection string options          |
| DstServerName   | destination SQL Server name               |
| DstDatabaseName | destination database name                 |
| DstConnOptions  | destination connection string options     |
| DisableFK       | disable foreign keys during purge process |

# Source Table
Defines tables to archive/purge:
| Column               | Description                                               |
| -------------------- | --------------------------------------------------------- |
| SourceTableId        | unique identifier                                         |
| SchemaName           | table schema                                              |
| TableName            | table name                                                |
| DataCopyBatchSize    | batch size for data copy                                  |
| KeyCopyBatchSize     | batch size for primary key copy                           |
| PurgeBatchSize       | batch size for purge                                      |
| KeyQuery             | query to select primary keys                              |
| Archive              | enable archiving                                          |
| Purge                | enable purge                                              |
| PurgeOrder           | order for purge execution                                 |
| DelayInterval        | delay between batches (*HH:mm:ss*)                        |
| AlwaysRunCheck       | forces reconciliation step every run                      |
| SrcWorkingTableName  | working table for source primary keys. Computed           |
| DstWorkingTableName  | working table for destination keys. Computed              |
| WorkingTableKeyName  | identity column name for working tables. Computed         |
| WorkingTableFlagName | processing flag column for source working table. Computed |

Note: *KeyQuery* should select only primary key column(s). Like this one:
```sql
select  OrderId
from    dbo.Order
where OrderDate >= dateadd(day, -1, cast(getdate() as date)) and OrderDate < cast(getdate() as date)
```

# Process State
Tracks progress:
| Column              | Description                         |
| ------------------- | ----------------------------------- |
| ProcessStateId      | unique identifier                   |
| SourceTableId       | table reference                     |
| KeyCopyDate         | primary key copy completion         |
| KeyMaxValue         | surrogate primary key max value     |
| LastArchivedKey     | last archived surrogate primary key |
| RowsArchived        | total rows archived                 |
| ArchiveCompleteDate | archive completion                  |
| LastPurgedKey       | last purged surrogate primary key   |
| RowsPurged          | total rows purged                   |
| PurgeCompleteDate   | purge completion                    |
| CompleteDate        | full completion                     |

# Usage example
```powershell
Invoke-EasyArchiving `
    -ConnStr 'Server=...;Database=easy_archiving;...' `
    -GroupName 'MyGroup' `
    -LogFile 'C:\logs\archive.log'
```