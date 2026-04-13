if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_InsertProcessState' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_InsertProcessState as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_InsertProcessState
	@SourceTableId	int
as
set nocount on

insert dbo.ProcessState(SourceTableId)
values (@SourceTableId)

select cast(scope_identity() as int) ProcessStateId
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_GetTableGroup' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_GetTableGroup as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_GetTableGroup
	@Name	sysname
as
set nocount on

select	TableGroupId,
		SrcServerName,
		SrcDatabaseName,
		SrcConnectionOptions,
		DstServerName,
		DstDatabaseName,
		DstConnectionOptions,
		DisableFK
from	dbo.TableGroup
where [Name] = @Name
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_GetSourceTable' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_GetSourceTable as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_GetSourceTable
	@TableGroupId	int
as
set nocount on

select	SourceTableId,
		SchemaName,
		TableName,
		DataCopyBatchSize,
		KeyCopyBatchSize,
		PurgeBatchSize,
		KeyQuery,
		Archive,
		Purge,
		PurgeOrder,
		DelayInterval,
		AlwaysRunCheck,
		SrcWorkingTableName,
		DstWorkingTableName,
		WorkingTableKeyName,
		WorkingTableFlagName
from	dbo.SourceTable
where Active = 1 and TableGroupId = @TableGroupId
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_GetIncompleteProcessState' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_GetIncompleteProcessState as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_GetIncompleteProcessState
	@SourceTableId	int
as
set nocount on

select top 1 ProcessStateId,
		KeyCopyDate,
		KeyMaxValue,
		LastArchivedKey,
		ArchiveCompleteDate,
		RowsArchived,
		LastPurgedKey,
		PurgeCompleteDate,
		RowsPurged
from	dbo.ProcessState
where SourceTableId = @SourceTableId and CompleteDate is null
order by ProcessStateId desc
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_UpdateProcessState' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_UpdateProcessState as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_UpdateProcessState
	@ProcessStateId		int,
	@KeyCopyDate		datetime2(7) = null,
	@KeyMaxValue		int = null,
	@LastArchivedKey	int = null,
	@ArchiveCompleteDate	datetime2(7) = null,
	@RowsArchived			int = null,
	@LastPurgedKey		int = null,
	@PurgeCompleteDate	datetime2(7) = null,
	@RowsPurged			int = null,
	@CompleteDate		datetime2(7) = null
as
set nocount on

update	dbo.ProcessState
set		KeyCopyDate = isnull(@KeyCopyDate, KeyCopyDate),
		KeyMaxValue = isnull(@KeyMaxValue, KeyMaxValue),
		LastArchivedKey = isnull(@LastArchivedKey, LastArchivedKey),
		ArchiveCompleteDate = isnull(@ArchiveCompleteDate, ArchiveCompleteDate),
		RowsArchived = isnull(@RowsArchived, RowsArchived),
		LastPurgedKey = isnull(@LastPurgedKey, LastPurgedKey),
		PurgeCompleteDate = isnull(@PurgeCompleteDate, PurgeCompleteDate),
		RowsPurged = isnull(@RowsPurged, RowsPurged),
		CompleteDate = isnull(@CompleteDate, CompleteDate),
		ModifyDate = sysutcdatetime()
where ProcessStateId = @ProcessStateId
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_GetBulkCopyData' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_GetBulkCopyData as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_GetBulkCopyData
	@ProcessStateId	int,
	@Debug			bit = 0
as
set nocount on

declare @SrcDatabaseName sysname, @SchemaName sysname, @TableName sysname, @SrcWorkingTableName sysname
declare @WorkingTableKeyName sysname, @WorkingTableFlagName sysname
declare @DataCopyBatchSize int, @LastArchivedKey int, @Query nvarchar(max)
declare @SelectColumns nvarchar(max), @JoinColumns nvarchar(max)

select	@SrcDatabaseName = gr.SrcDatabaseName,
		@SchemaName = ta.SchemaName,
		@TableName = ta.TableName,
		@DataCopyBatchSize = ta.[DataCopyBatchSize],
		@SrcWorkingTableName = ta.SrcWorkingTableName,
		@WorkingTableKeyName = ta.WorkingTableKeyName,
		@WorkingTableFlagName = ta.WorkingTableFlagName,
		@LastArchivedKey = isnull(st.LastArchivedKey, 0)
from	dbo.ProcessState st
		join dbo.SourceTable ta
		on ta.SourceTableId = st.SourceTableId
		join dbo.TableGroup gr
		on gr.TableGroupId = ta.TableGroupId
where st.ProcessStateId = @ProcessStateId

-- get table columns, without computed and timestamp/rowversion columns
set @Query = '-- dbo.stp_GetBulkCopyData
set @SelectColumns = (
	select	''so.['' + COLUMN_NAME + ''], ''
	from	[' + @SrcDatabaseName + '].INFORMATION_SCHEMA.COLUMNS co
	where TABLE_SCHEMA = ''' + @SchemaName + ''' and TABLE_NAME = ''' + @TableName + '''
		and not exists
		(
		select	1
		from	[' + @SrcDatabaseName + '].sys.columns sc
		where sc.[object_id] = object_id(''' + @SrcDatabaseName + '.'' + co.TABLE_SCHEMA + ''.'' + co.TABLE_NAME) and sc.[name] = co.COLUMN_NAME and sc.is_computed = 1
		)
		and DATA_TYPE not in(''timestamp'',''rowversion'')
	for xml path('''')
)'
if @Query is null
begin
	raiserror('@Query(0) is null for dbo.stp_GetBulkCopyData', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@SelectColumns nvarchar(max) output', @SelectColumns = @SelectColumns output
set @SelectColumns = left(@SelectColumns, len(@SelectColumns) - 1)

-- get primary key columns for join
set @Query = '-- dbo.stp_GetBulkCopyData
set @JoinColumns = (
	select	''so.['' + ccu.COLUMN_NAME + ''] = wo.['' + ccu.COLUMN_NAME + ''] and ''
	from	[' + @SrcDatabaseName + '].INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
			join [' + @SrcDatabaseName + '].INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
			on ccu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME and ccu.TABLE_NAME = tc.TABLE_NAME and ccu.TABLE_SCHEMA = tc.TABLE_SCHEMA
	where tc.TABLE_SCHEMA = ''' + @SchemaName + ''' and tc.TABLE_NAME = ''' + @TableName + '''
		and tc.CONSTRAINT_TYPE = ''PRIMARY KEY''
	for xml path('''')
)'
if @Query is null
begin
	raiserror('@Query(1) is null for dbo.stp_GetBulkCopyData', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@JoinColumns nvarchar(max) output', @JoinColumns = @JoinColumns output
set @JoinColumns = left(@JoinColumns, len(@JoinColumns) - 4)

set @Query = '-- dbo.stp_GetBulkCopyData
select ' + @SelectColumns + '
from	(
		select	t.*
		from	dbo.[' + @SrcWorkingTableName + '] t
		where t.[' + @WorkingTableKeyName + '] > @LastArchivedKey and t.[' + @WorkingTableKeyName + '] <= @LastArchivedKey + @DataCopyBatchSize
			and [' + @WorkingTableFlagName + '] = 0
		) wo
		join [' + @SrcDatabaseName + '].[' + @SchemaName + '].[' + @TableName + '] so
		on ' + @JoinColumns + '
option(optimize for(@DataCopyBatchSize = ' + cast(@DataCopyBatchSize as nvarchar(100)) + ', @LastArchivedKey = 0))'
if @Query is null
begin
	raiserror('@Query(2) is null for dbo.stp_GetBulkCopyData', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@DataCopyBatchSize int, @LastArchivedKey int', @DataCopyBatchSize = @DataCopyBatchSize, @LastArchivedKey = @LastArchivedKey
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_PurgeData' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_PurgeData as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_PurgeData
	@ProcessStateId	int,
	@Debug			bit = 0
as
set nocount on

declare @SrcDatabaseName sysname, @SchemaName sysname, @TableName sysname, @SrcWorkingTableName sysname
declare @WorkingTableKeyName sysname, @WorkingTableFlagName sysname
declare @PurgeBatchSize int, @LastPurgedKey int, @Query nvarchar(max)
declare @JoinColumns nvarchar(max)

select	@SrcDatabaseName = gr.SrcDatabaseName,
		@SchemaName = ta.SchemaName,
		@TableName = ta.TableName,
		@PurgeBatchSize = ta.PurgeBatchSize,
		@SrcWorkingTableName = ta.SrcWorkingTableName,
		@WorkingTableKeyName = ta.WorkingTableKeyName,
		@WorkingTableFlagName = ta.WorkingTableFlagName,
		@LastPurgedKey = isnull(st.LastPurgedKey, 0)
from	dbo.ProcessState st
		join dbo.SourceTable ta
		on ta.SourceTableId = st.SourceTableId
		join dbo.TableGroup gr
		on gr.TableGroupId = ta.TableGroupId
where st.ProcessStateId = @ProcessStateId

-- get primary key columns for join
set @Query = '-- dbo.stp_PurgeData
set @JoinColumns = (
	select	''so.['' + ccu.COLUMN_NAME + ''] = wo.['' + ccu.COLUMN_NAME + ''] and ''
	from	[' + @SrcDatabaseName + '].INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
			join [' + @SrcDatabaseName + '].INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu
			on ccu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME and ccu.TABLE_NAME = tc.TABLE_NAME and ccu.TABLE_SCHEMA = tc.TABLE_SCHEMA
	where tc.TABLE_SCHEMA = ''' + @SchemaName + ''' and tc.TABLE_NAME = ''' + @TableName + '''
		and tc.CONSTRAINT_TYPE = ''PRIMARY KEY''
	for xml path('''')
)'
if @Query is null
begin
	raiserror('@Query(0) is null for dbo.stp_PurgeData', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@JoinColumns nvarchar(max) output', @JoinColumns = @JoinColumns output
set @JoinColumns = left(@JoinColumns, len(@JoinColumns) - 4)

set @Query = '-- dbo.stp_PurgeData
delete so
from	(
		select	t.*
		from	dbo.[' + @SrcWorkingTableName + '] t
		where t.[' + @WorkingTableKeyName + '] > @LastPurgedKey and t.[' + @WorkingTableKeyName + '] <= @LastPurgedKey + @PurgeBatchSize
		) wo
		join [' + @SrcDatabaseName + '].[' + @SchemaName + '].[' + @TableName + '] so
		on ' + @JoinColumns + '
option(optimize for(@PurgeBatchSize = ' + cast(@PurgeBatchSize as nvarchar(100)) + ', @LastPurgedKey = 0))

select @@rowcount RowsPurgedForBatch'
if @Query is null
begin
	raiserror('@Query(1) is null for dbo.stp_PurgeData', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@PurgeBatchSize int, @LastPurgedKey int', @PurgeBatchSize = @PurgeBatchSize, @LastPurgedKey = @LastPurgedKey
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_UpdateKeyMaxValue' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_UpdateKeyMaxValue as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_UpdateKeyMaxValue
	@ProcessStateId	int,
	@Debug			bit = 0
as
set nocount on

declare @SchemaName sysname, @TableName sysname, @SrcWorkingTableName sysname
declare @WorkingTableKeyName sysname, @KeyMaxValue int
declare @Query nvarchar(max)

select	@SchemaName = ta.SchemaName,
		@TableName = ta.TableName,
		@SrcWorkingTableName = ta.SrcWorkingTableName,
		@WorkingTableKeyName = ta.WorkingTableKeyName
from	dbo.ProcessState ast
		join dbo.SourceTable ta
		on ta.SourceTableId = ast.SourceTableId
		join dbo.TableGroup gr
		on gr.TableGroupId = ta.TableGroupId
where ast.ProcessStateId = @ProcessStateId

set @Query = '-- dbo.stp_UpdateKeyMaxValue
select	@KeyMaxValue = isnull(max([' + @WorkingTableKeyName + ']), 0)
from	dbo.[' + @SrcWorkingTableName + ']'
if @Query is null
begin
	raiserror('@Query(0) is null for dbo.stp_UpdateKeyMaxValue', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@KeyMaxValue int output', @KeyMaxValue = @KeyMaxValue output

update	dbo.ProcessState
set		KeyMaxValue = @KeyMaxValue,
		ModifyDate = sysutcdatetime()
where ProcessStateId = @ProcessStateId

select @KeyMaxValue KeyMaxValue
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_FixLastArchivedKey' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_FixLastArchivedKey as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_FixLastArchivedKey
	@ProcessStateId	int,
	@Debug			bit = 0
as
set nocount on

declare @SchemaName sysname, @TableName sysname, @SrcWorkingTableName sysname, @DstWorkingTableName sysname
declare @WorkingTableKeyName sysname, @WorkingTableFlagName sysname, @KeyMaxValue int
declare @CurrentLastArchivedKey int, @NewLastArchivedKey int
declare @Query nvarchar(max), @JoinColumns nvarchar(max)

select	@SchemaName = ta.SchemaName,
		@TableName = ta.TableName,
		@SrcWorkingTableName = ta.SrcWorkingTableName,
		@DstWorkingTableName = ta.DstWorkingTableName,
		@WorkingTableKeyName = ta.WorkingTableKeyName,
		@WorkingTableFlagName = ta.WorkingTableFlagName,
		@CurrentLastArchivedKey = ast.LastArchivedKey,
		@KeyMaxValue = ast.KeyMaxValue
from	dbo.ProcessState ast
		join dbo.SourceTable ta
		on ta.SourceTableId = ast.SourceTableId
where ast.ProcessStateId = @ProcessStateId

set @Query = '-- dbo.stp_FixLastArchivedKey
set @JoinColumns = (
	select	''de.['' + co.COLUMN_NAME + ''] = so.['' + co.COLUMN_NAME + ''] and ''
	from	INFORMATION_SCHEMA.COLUMNS co
	where TABLE_SCHEMA = ''dbo'' and TABLE_NAME = ''' + @SrcWorkingTableName + '''
		and co.COLUMN_NAME not in (''' + @WorkingTableKeyName + ''', ''' + @WorkingTableFlagName + ''')
	for xml path('''')
)'
if @Query is null
begin
	raiserror('@Query(0) is null for dbo.stp_FixLastArchivedKey', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@JoinColumns nvarchar(max) output', @JoinColumns = @JoinColumns output
if @JoinColumns is null raiserror('@JoinColumns is null', 16, 1)

set @JoinColumns = left(@JoinColumns, len(@JoinColumns) - 4)
set @Query = '-- dbo.stp_FixLastArchivedKey
update	so
set		[' + @WorkingTableFlagName + '] = 1
from	dbo.[' + @SrcWorkingTableName + '] so
		join dbo.[' + @DstWorkingTableName + '] de
		on ' + @JoinColumns + '

select	@NewLastArchivedKey = min([' + @WorkingTableKeyName + ']) - 1
from	dbo.[' + @SrcWorkingTableName + ']
where [' + @WorkingTableFlagName + '] = 0'
if @Query is null
begin
	raiserror('@Query(1) is null for dbo.stp_FixLastArchivedKey', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@NewLastArchivedKey int output', @NewLastArchivedKey = @NewLastArchivedKey output

set @NewLastArchivedKey = isnull(@NewLastArchivedKey, @KeyMaxValue)

if @NewLastArchivedKey <> @CurrentLastArchivedKey or @CurrentLastArchivedKey is null
begin
	update	dbo.ProcessState
	set		LastArchivedKey = @NewLastArchivedKey,
			ModifyDate = sysutcdatetime()
	where ProcessStateId = @ProcessStateId
end

select @NewLastArchivedKey LastArchivedKey
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_DisableEnableFK' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_DisableEnableFK as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_DisableEnableFK
	@ProcessStateId	int,
	@Disable		bit,
	@Debug			bit = 0
as
set nocount on

declare @SrcDatabaseName sysname, @SchemaName sysname, @TableName sysname
declare @Query nvarchar(max), @AlterFK nvarchar(max)

select	@SrcDatabaseName = gr.SrcDatabaseName,
		@SchemaName = ta.SchemaName,
		@TableName = ta.TableName
from	dbo.ProcessState st
		join dbo.SourceTable ta
		on ta.SourceTableId = st.SourceTableId
		join dbo.TableGroup gr
		on gr.TableGroupId = ta.TableGroupId
where st.ProcessStateId = @ProcessStateId

set @Query = '-- dbo.stp_DisableEnableFK
set @AlterFK = (
select	case	when @Disable = 1 then ''alter table [' + @SrcDatabaseName + '].['' + pa.TABLE_SCHEMA + ''].['' + pa.TABLE_NAME + ''] nocheck constraint ['' + pa.CONSTRAINT_NAME + ''];''
				else ''alter table [' + @SrcDatabaseName + '].['' + pa.TABLE_SCHEMA + ''].['' + pa.TABLE_NAME + ''] with nocheck check constraint ['' + pa.CONSTRAINT_NAME + ''];''
		end
from	[' + @SrcDatabaseName + '].INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS fk
		join [' + @SrcDatabaseName + '].INFORMATION_SCHEMA.KEY_COLUMN_USAGE pa
		on pa.CONSTRAINT_SCHEMA = fk.CONSTRAINT_SCHEMA and pa.CONSTRAINT_NAME = fk.CONSTRAINT_NAME 
		join [' + @SrcDatabaseName + '].INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS ref
		on ref.CONSTRAINT_SCHEMA = fk.UNIQUE_CONSTRAINT_SCHEMA and ref.CONSTRAINT_NAME = fk.UNIQUE_CONSTRAINT_NAME 
			and ref.ORDINAL_POSITION = pa.ORDINAL_POSITION
where ref.TABLE_SCHEMA = ''' + @SchemaName + ''' and ref.TABLE_NAME = ''' + @TableName + '''
for xml path('''')
)'
if @Query is null
begin
	raiserror('@Query(0) is null for dbo.stp_DisableEnableFK', 16, 1)
end
if @Debug = 1
begin
	print @Query
end
exec sp_executesql @Query, N'@AlterFK nvarchar(max) output, @Disable bit', @AlterFK = @AlterFK output, @Disable = @Disable

if @AlterFK is not null
begin
	exec sp_executesql @AlterFK
end
go
