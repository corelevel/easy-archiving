if not exists (
	select	1
	from	INFORMATION_SCHEMA.TABLES
	where TABLE_NAME = N'TableGroup' and TABLE_SCHEMA = N'dbo' and TABLE_TYPE = N'BASE TABLE')
begin
	create table dbo.TableGroup
	(
		TableGroupId			int identity(1,1) not null,
		[Name]					sysname not null,

		CreateDate				datetime2(7) not null constraint DF_TableGroup__CreateDate default(sysdatetime()),
		SrcServerName			sysname not null,	-- source server name
		SrcDatabaseName			sysname not null,	-- source database name
		SrcConnectionOptions	nvarchar(4000) null,-- connection string options like ApplicationIntent, time out, user name, password, etc

		DstServerName			sysname not null,	-- destination server name
		DstDatabaseName			sysname not null,	-- destination database name
		DstConnectionOptions	nvarchar(4000) null,-- connection string options like ApplicationIntent, time out, user name, password, etc

		DisableFK				bit not null		-- disable FK before purge
	)

	alter table dbo.TableGroup add constraint PK_TableGroup primary key clustered (TableGroupId)
	with (data_compression = page)

	create unique nonclustered index IXU_TableGroup__Name on dbo.TableGroup([Name])
	with (data_compression = page)
end
go

if not exists (
	select	1
	from	INFORMATION_SCHEMA.TABLES
	where TABLE_NAME = N'SourceTable' and TABLE_SCHEMA = N'dbo' and TABLE_TYPE = N'BASE TABLE')
begin
	create table dbo.SourceTable
	(
		SourceTableId		int identity(1,1) not null,
		TableGroupId		int not null,

		SchemaName			sysname not null,
		TableName			sysname not null,
		CreateDate			datetime2(7) not null constraint DF_SourceTable__CreateDate default(sysdatetime()),

		Active				bit not null,

		DataCopyBatchSize	int not null,			-- batch size for data copy
		KeyCopyBatchSize	int not null,			-- batch size for keys copy
		PurgeBatchSize		int not null,			-- batch size for purge
		KeyQuery			nvarchar(max) not null,	-- to select primary keys values from the source

		Archive				bit not null,			-- can be archived

		Purge				bit not null,			-- can be purged
		PurgeOrder			smallint not null,		-- used to get purge order

		DelayInterval		char(8) not null,		-- 'hh:mm:ss'

		AlwaysRunCheck		bit not null,			-- always check for previously copied records

		SrcWorkingTableName as SchemaName + '_' + TableName + '__src',	-- working table name for source primary keys
		DstWorkingTableName as SchemaName + '_' + TableName + '__dst',	-- working table name for destination primary keys
		WorkingTableKeyName as TableName + '__key',		-- working table PK column name
		WorkingTableFlagName as TableName + '__skip'	-- 0 - ok, 1 - means row is already copied and must be skipped
	)

	alter table dbo.SourceTable add constraint PK_SourceTable primary key clustered (SourceTableId)
	with (data_compression = page)

	create unique nonclustered index IXU_SourceTable__TableGroupId_SchemaName_TableName on dbo.SourceTable (TableGroupId, SchemaName, TableName)
	with (data_compression = page)

	create nonclustered index IX_SourceTable__TableGroupId on dbo.SourceTable(TableGroupId)
	with (data_compression = page)

	alter table dbo.SourceTable add constraint FK_SourceTable_TableGroup__TableGroupId foreign key (TableGroupId)
	references dbo.TableGroup (TableGroupId)
end
go

if not exists (
	select	1
	from	INFORMATION_SCHEMA.TABLES
	where TABLE_NAME = N'ProcessState' and TABLE_SCHEMA = N'dbo' and TABLE_TYPE = N'BASE TABLE')
begin
	create table dbo.ProcessState
	(
		ProcessStateId		int identity(1,1) not null,
		SourceTableId		int not null,
		CreateDate			datetime2(7) not null constraint DF_ProcessState__CreateDate default(sysdatetime()),
		ModifyDate			datetime2(7) not null constraint DF_ProcessState__ModifyDate default(sysdatetime()),

		KeyCopyDate			datetime2(7) null,	-- date of primary keys copy

		KeyMaxValue			int null,

		LastArchivedKey		int null,			-- last copied surrogate primary key
		ArchiveCompleteDate	datetime2(7) null,	-- archiving complete date
		RowsArchived		int null,			-- rows count

		LastPurgedKey		int null,			-- last purged surrogate primary key
		PurgeCompleteDate	datetime2(7) null,	-- purging complete date
		RowsPurged			int null,			-- rows count

		CompleteDate		datetime2(7) null
	)

	alter table dbo.ProcessState add constraint PK_ProcessState primary key clustered (ProcessStateId)
	with (data_compression = page)

	create nonclustered index IXF_ProcessState__SourceTableId ON dbo.ProcessState(SourceTableId) where CompleteDate is null
	with (data_compression = page)

	create nonclustered index IX_ProcessState__SourceTableId ON dbo.ProcessState(SourceTableId)
	with (data_compression = page)

	alter table dbo.ProcessState add constraint FK_ProcessState_SourceTable__SourceTableId foreign key (SourceTableId)
	references dbo.SourceTable (SourceTableId)
end
go