use [easy-archiving]
go
set nocount on
go
insert dbo.TableGroup
(
	[Name],
	SrcServerName,
	SrcDatabaseName,
	SrcConnectionOptions,
	DstServerName,
	DstDatabaseName,
	DstConnectionOptions,
	DisableFK
)
select	'group01' [Name],
		'(local)' SrcServerName,
		'StackOverflow2013' SrcDatabaseName,
		'Connection Timeout=5;Encrypt=False;User Id=sa;Password=P1s-Unsee-Me;Application Name=easy-archiving;' SrcConnectionOptions,
		'tcp:localhost,11433' DstServerName,
		'tempdb' DstDatabaseName,
		'Connection Timeout=5;Encrypt=False;User Id=sa;Password=P1s-Unsee-Me;Application Name=easy-archiving;' DstConnectionOptions,
		0 DisableFK
go
insert dbo.SourceTable
(
	TableGroupId,
	SchemaName,
	TableName,
	Active,
	DataCopyBatchSize,
	KeyCopyBatchSize,
	PurgeBatchSize,
	KeyQuery,
	Archive,
	Purge,
	PurgeOrder,
	DelayInterval,
	AlwaysRunCheck
)
select  1 TableGroupId,
		'dbo' SchemaName,
		'Users' TableName,
		1 Active,
		100 DataCopyBatchSize,
		100 KeyCopyBatchSize,
		50 PurgeBatchSize,
		'select Id from dbo.Users where CreationDate <= ''2008-08-15''' KeyQuery,
		1 Archive,
		0 Purge,
		1 PurgeOrder,
		'00:00:01' DelayInterval,
		1 AlwaysRunCheck
go