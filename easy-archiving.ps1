using namespace System.Data.SqlClient
using namespace System.Collections.Generic

function Write-LogMessage {
	Param (
		[parameter(Mandatory)]
		[string]$Message,

		[string]$LogFile
	)
	$line = (Get-Date).ToString('[MM/dd/yy HH:mm:ss.ff]') + ' ' + $Message
	Write-Verbose $line
	if ($LogFile) {
		Add-Content -Path $LogFile -Value $line
	}
}

function Get-DelayIntervalInSeconds {
	Param (
		[parameter(Mandatory)]
		[string]$DelayInterval
	)

	$d1 = [datetime]::ParseExact("01010001 $DelayInterval", 'ddMMyyyy HH:mm:ss', $null)
	$d2 = [datetime]::ParseExact('01010001 00:00:00', 'ddMMyyyy HH:mm:ss', $null)

	$d1.Subtract($d2).TotalSeconds
}

class TableColumn {
	[string]$Name
	[string]$DataType
	[string]$Collation
	[bool]$Computed
	[bool]$Nullable
}

class IndexColumn {
	[int]$Id
	[string]$Name
	[string]$Order
}

class Index {
	[string]$Name
	[bool]$Unique
}

class TableGroup {
	[int]$Id
	[string]$Name

	[string]$SrcServerName
	[string]$SrcDatabaseName

	[string]$DstServerName
	[string]$DstDatabaseName

	[bool]$DisableFK

	$ArcSqlConn = [SqlConnection]::new()
	$SrcSqlConn = [SqlConnection]::new()
	$DstSqlConn = [SqlConnection]::new()

	$SourceTables = [List[Table]]::new()

	TableGroup([string]$ConnStr, [string]$groupName) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sb = [SqlConnectionStringBuilder]::new($ConnStr)

			$this.ArcSqlConn.ConnectionString = $sb.ConnectionString
			$this.ArcSqlConn.Open()

			$sqlCmd = [SqlCommand]::new('dbo.stp_GetTableGroup', $this.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pName = $sqlCmd.Parameters.Add('@Name', [System.Data.SqlDbType]::NVarChar)
			$pName.Value = $groupName

			$sqlReader = $sqlCmd.ExecuteReader()
			
			if ($sqlReader.Read()) {
				$this.Id = $sqlReader['TableGroupId']
				$this.Name = $groupName

				# source database server
				$this.SrcServerName = $sqlReader['SrcServerName']
				$this.SrcDatabaseName = $sqlReader['SrcDatabaseName']

				$sb = [SqlConnectionStringBuilder]::new($sqlReader['SrcConnectionOptions'])
				$sb['Data Source'] = $this.SrcServerName
				$sb['Initial Catalog'] = $this.SrcDatabaseName
				$this.SrcSqlConn.ConnectionString = $sb.ConnectionString
				$this.SrcSqlConn.Open()

				# destination database server
				$this.DstServerName = $sqlReader['DstServerName']
				$this.DstDatabaseName = $sqlReader['DstDatabaseName']

				$sb = [SqlConnectionStringBuilder]::new($sqlReader['DstConnectionOptions'])
				$sb['Data Source'] = $this.DstServerName
				$sb['Initial Catalog'] = $this.DstDatabaseName
				$sb['Persist Security Info'] = 'True'
				$this.DstSqlConn.ConnectionString = $sb.ConnectionString
				$this.DstSqlConn.Open()

				$this.DisableFK = $sqlReader['DisableFK']
			}
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	ReadSourceTables() {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_GetSourceTable', $this.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pTableGroupId = $sqlCmd.Parameters.Add('@TableGroupId', [System.Data.SqlDbType]::Int)
			$pTableGroupId.Value = $this.Id

			$sqlReader = $sqlCmd.ExecuteReader()
			while ($sqlReader.Read()) {
				$this.SourceTables.Add(
					[Table]@{
						Id = $sqlReader['SourceTableId']
						SchemaName = $sqlReader['SchemaName']
						TableName = $sqlReader['TableName']
						DataCopyBatchSize = $sqlReader['DataCopyBatchSize']
						KeyCopyBatchSize = $sqlReader['KeyCopyBatchSize']
						PurgeBatchSize = $sqlReader['PurgeBatchSize']
						KeyQuery = $sqlReader['KeyQuery']
						Archive = $sqlReader['Archive']
						Purge = $sqlReader['Purge']
						PurgeOrder = $sqlReader['PurgeOrder']
						DelayIntervalInSeconds = Get-DelayIntervalInSeconds -DelayInterval $sqlReader['DelayInterval']
						AlwaysRunCheck = $sqlReader['AlwaysRunCheck']
						SrcWorkingTableName = $sqlReader['SrcWorkingTableName']
						DstWorkingTableName = $sqlReader['DstWorkingTableName']
						WorkingTableKeyName = $sqlReader['WorkingTableKeyName']
						WorkingTableFlagName = $sqlReader['WorkingTableFlagName']
						Group = $this
					}
				)
			}
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	Dispose() {
		if ($this.ArcSqlConn) { $this.ArcSqlConn.Dispose() }
		if ($this.SrcSqlConn) { $this.SrcSqlConn.Dispose() }
		if ($this.DstSqlConn) { $this.DstSqlConn.Dispose() }
	}
}

class ProcessState {
	[int]$Id
	[int]$SourceTableId
	[DateTime]$CreateDate

	[DateTime]$KeyCopyDate
	[int]$KeyMaxValue

	[int]$LastArchivedKey
	[DateTime]$LastArchivedDate
	[int]$RowsCopied

	[int]$LastPurgedKey
	[DateTime]$LastPurgedDate
	[int]$RowsPurged

	[DateTime]$CompleteDate

	[bool]$IncompleteProcess

	[int]$RowsCopiedForBatch
	[int]$RowsPurgedForBatch

	[SqlConnection]$SqlConn

	UpdateKeyMaxValue() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_UpdateKeyMaxValue', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id

			$this.KeyMaxValue = [int]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	UpdateKeyCopyDate() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_UpdateProcessState', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id
			$pKeyCopyDate = $sqlCmd.Parameters.Add('@KeyCopyDate', [System.Data.SqlDbType]::DateTime)
			$pKeyCopyDate.Value = [DateTime]::Now

			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	UpdateCompleteDate() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_UpdateProcessState', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id
			$pCompleteDate = $sqlCmd.Parameters.Add('@CompleteDate', [System.Data.SqlDbType]::DateTime)
			$pCompleteDate.Value = [DateTime]::Now

			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	UpdateArchiveState() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_UpdateProcessState', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id
			$pLastArchivedKey = $sqlCmd.Parameters.Add('@LastArchivedKey', [System.Data.SqlDbType]::Int)
			$pLastArchivedKey.Value = $this.LastArchivedKey
			$pRowsCopied = $sqlCmd.Parameters.Add('@RowsCopied', [System.Data.SqlDbType]::Int)
			$pRowsCopied.Value = $this.RowsCopied
			$pLastArchivedDate = $sqlCmd.Parameters.Add('@LastArchivedDate', [System.Data.SqlDbType]::DateTime)
			$pLastArchivedDate.Value = [DateTime]::Now

			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	UpdatePurgeState() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_UpdateProcessState', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id
			$pLastPurgedKey = $sqlCmd.Parameters.Add('@LastPurgedKey', [System.Data.SqlDbType]::Int)
			$pLastPurgedKey.Value = $this.LastPurgedKey
			$pRowsPurged = $sqlCmd.Parameters.Add('@RowsPurged', [System.Data.SqlDbType]::Int)
			$pRowsPurged.Value = $this.RowsPurged
			$pLastPurgedDate = $sqlCmd.Parameters.Add('@LastPurgedDate', [System.Data.SqlDbType]::DateTime)
			$pLastPurgedDate.Value = [DateTime]::Now

			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	Create() {
		if ($this.Id -ne 0) {
			return
		}
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_InsertProcessState', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pSourceTableId = $sqlCmd.Parameters.Add('@SourceTableId', [System.Data.SqlDbType]::Int)
			$pSourceTableId.Value = $this.SourceTableId

			$this.Id = [int]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	[bool]ArchiveProcessHasRowsForNextBatch() {
		return ($this.LastArchivedKey -lt $this.KeyMaxValue)
	}

	[bool]PurgeProcessHasRowsForNextBatch() {
		return ($this.LastPurgedKey -lt $this.KeyMaxValue)
	}

	[bool]IsKeysCopied() {
		return ($this.KeyCopyDate -ne [DateTime]::MinValue)
	}

	FixAndGetLastArchivedKey() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_FixLastArchivedKey', $this.SqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id

			$this.LastArchivedKey = [long]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	SetRowsCopied($count) {
		$this.RowsCopiedForBatch = [int]$count
	}
}

class Table {
	[int]$Id
	[string]$SchemaName
	[string]$TableName
	[int]$DataCopyBatchSize
	[int]$KeyCopyBatchSize
	[int]$PurgeBatchSize
	[string]$KeyQuery
	[bool]$Archive
	[bool]$Purge
	[int]$PurgeOrder
	[int]$DelayIntervalInSeconds
	[bool]$AlwaysRunCheck
	[string]$SrcWorkingTableName
	[string]$DstWorkingTableName
	[string]$WorkingTableKeyName
	[string]$WorkingTableFlagName

	[TableGroup]$Group
	[ProcessState]$State
	[Dictionary[string, TableColumn]]$SrcColumns
	[Index]$SrcPk
	[Index]$SrcCl
	[List[IndexColumn]]$SrcPkColumns
	[List[IndexColumn]]$SrcClColumns
	[Dictionary[string, TableColumn]]$DstColumns
	[Index]$DstPk
	[Index]$DstCl
	[List[IndexColumn]]$DstPkColumns
	[List[IndexColumn]]$DstClColumns
	$MissedColumns = [List[TableColumn]]::new()
	[bool]$FKDisabled = $false

	GetState() {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$this.State = [ProcessState]@{
				SourceTableId = $this.Id
				SqlConn = $this.Group.ArcSqlConn
				IncompleteProcess = $false
			}

			$sqlCmd = [SqlCommand]::new('dbo.stp_GetIncompleteProcessState', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pSourceTableId = $sqlCmd.Parameters.Add('@SourceTableId', [System.Data.SqlDbType]::NVarChar, 128)
			$pSourceTableId.Value = $this.Id

			$sqlReader = $sqlCmd.ExecuteReader()

			if ($sqlReader.Read()) {
				$this.State.Id = $sqlReader['ProcessStateId']

				if ($sqlReader['KeyCopyDate'] -isnot [System.DBNull]) {
					$this.State.KeyCopyDate = $sqlReader['KeyCopyDate']
				}
				if ($sqlReader['KeyMaxValue'] -isnot [System.DBNull]) {
					$this.State.KeyMaxValue = $sqlReader['KeyMaxValue']
				}
				if ($sqlReader['LastArchivedKey'] -isnot [System.DBNull]) {
					$this.State.LastArchivedKey = $sqlReader['LastArchivedKey']
				}
				if ($sqlReader['LastArchivedDate'] -isnot [System.DBNull]) {
					$this.State.LastArchivedDate = $sqlReader['LastArchivedDate']
				}
				if ($sqlReader['RowsCopied'] -isnot [System.DBNull]) {
					$this.State.RowsCopied = $sqlReader['RowsCopied']
				}
				if ($sqlReader['LastPurgedKey'] -isnot [System.DBNull]) {
					$this.State.LastPurgedKey = $sqlReader['LastPurgedKey']
				}
				if ($sqlReader['LastPurgedDate'] -isnot [System.DBNull]) {
					$this.State.LastPurgedDate = $sqlReader['LastPurgedDate']
				}
				if ($sqlReader['RowsPurged'] -isnot [System.DBNull]) {
					$this.State.RowsPurged = $sqlReader['RowsPurged']
				}

				$this.State.IncompleteProcess = $true
			}
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	[bool]IsTableExistsInSource() {
		return [Table]::IsTableExists($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
	}

	[bool]IsTableExistsInDestination() {
		return [Table]::IsTableExists($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
	}

	[bool]IsTableSchemaExistsInDestination() {
		return [Table]::IsTableSchemaExists($this.SchemaName, $this.Group.DstSqlConn)
	}

	static [bool]IsTableExists([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select	case when exists
			(
			select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_SCHEMA = @SchemaName
				and TABLE_NAME = @TableName
				and TABLE_TYPE = 'BASE TABLE'
			)
			then 1
			else 0
		end v
'@
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@SchemaName", [System.Data.SqlDbType]::NVarChar, 128).Value = $schemaName
			$sqlCmd.Parameters.Add("@TableName", [System.Data.SqlDbType]::NVarChar, 128).Value = $tableName
			return [bool]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [bool]IsTableSchemaExists([string]$schemaName, [SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select case when exists (select	1 from sys.schemas where [name] = @SchemaName) then 1 else 0 end v
'@
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@SchemaName", [System.Data.SqlDbType]::NVarChar, 128).Value = $schemaName
			return [bool]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [string]GetColumnDefinition([TableColumn]$c) {
		$col = "[$($c.Name)] $($c.DataType)"
		if ($c.Collation) {
			$col += " collate $($c.Collation)"
		}
		$col += if ($c.Nullable) { ' null' } else { ' not null' }
		return $col
	}

	ReadSrcTableColumns() {
		$this.SrcColumns = [Table]::GetTableColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcPk = [Table]::GetTablePrimaryKeyIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcCl = [Table]::GetTableClusteredIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcPkColumns = [Table]::GetTablePrimaryColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcClColumns = [Table]::GetTableClusteredColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
	}

	ReadDstTableColumns() {
		$this.DstColumns = [Table]::GetTableColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstPk = [Table]::GetTablePrimaryKeyIndex($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstCl = [Table]::GetTableClusteredIndex($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstPkColumns = [Table]::GetTablePrimaryColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstClColumns = [Table]::GetTableClusteredColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
	}

	static [Dictionary[string, TableColumn]] GetTableColumns([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select	COLUMN_NAME [Name],
		DATA_TYPE +
			case
				when DATA_TYPE in ('decimal','numeric')
					then '(' + cast(NUMERIC_PRECISION as varchar) + ', ' + cast(NUMERIC_SCALE as varchar) + ')'
				when DATA_TYPE in ('varchar','char','varbinary','binary','nvarchar','nchar')
					then coalesce('(' + case when CHARACTER_MAXIMUM_LENGTH = -1 then 'max' else cast(CHARACTER_MAXIMUM_LENGTH as varchar) end + ')', '') 
				else ''
			end DataType,
        COLLATION_NAME [Collation],
		columnproperty(object_id(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsComputed') Computed,
		case when IS_NULLABLE = 'YES' then 1 else 0 end Nullable
from	INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = @SchemaName and TABLE_NAME = @TableName
	and DATA_TYPE not in('timestamp','rowversion')
'@

		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@SchemaName", [System.Data.SqlDbType]::NVarChar, 128).Value = $schemaName
			$sqlCmd.Parameters.Add("@TableName", [System.Data.SqlDbType]::NVarChar, 128).Value = $tableName
			$sqlReader = $sqlCmd.ExecuteReader()
			$columns = [Dictionary[string, TableColumn]]::new([System.StringComparer]::OrdinalIgnoreCase)

			while ($sqlReader.Read()) {
				$columns[$sqlReader['Name']] = ([TableColumn]@{
					Name = $sqlReader['Name']
					DataType = $sqlReader['DataType']
					Collation = if ($sqlReader['Collation'] -isnot [System.DBNull]) { $sqlReader['Collation'] } else { '' }
					Computed = $sqlReader['Computed']
					Nullable = $sqlReader['Nullable']
				})
			}
			return $columns
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [List[IndexColumn]] GetTableClusteredColumns([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	ic.index_column_id ColumnId,
		c.[name] ColumnName,
		case when ic.is_descending_key = 1 then 'desc' else 'asc' end [Order]
from	sys.indexes i
		join sys.index_columns ic
		on ic.[object_id] = i.[object_id] and ic.index_id = i.index_id
		join sys.columns c
		on c.[object_id] = ic.[object_id] and c.column_id = ic.column_id
where i.[object_id] = object_id(@ObjectName)
  and i.[type] = 1
  and ic.key_ordinal > 0
"@

		return [Table]::GetTableIndexColumns($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [List[IndexColumn]] GetTablePrimaryColumns([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	ic.key_ordinal ColumnId,
		c.[name] ColumnName,
		case when ic.is_descending_key = 1 then 'desc' else 'asc' end [Order]
from	sys.key_constraints kc
		join sys.indexes i
		on i.[object_id] = kc.parent_object_id and i.index_id = kc.unique_index_id
		join sys.index_columns ic 
		on ic.[object_id] = i.[object_id] and ic.index_id = i.index_id
		JOIN sys.columns c 
		on c.[object_id] = ic.[object_id] and c.column_id = ic.column_id
where kc.[type] = 'PK'
  and kc.parent_object_id = object_id(@ObjectName)
"@

		return [Table]::GetTableIndexColumns($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [List[IndexColumn]] GetTableIndexColumns([string]$query, [string]$objectName, [SqlConnection]$sqlConnection) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $sqlConnection) 
			$sqlCmd.Parameters.Add("@ObjectName", [System.Data.SqlDbType]::NVarChar, 257).Value = $objectName
			$sqlReader = $sqlCmd.ExecuteReader()
			$columns = [List[IndexColumn]]::new()

			while ($sqlReader.Read()) {
				$columns.Add([IndexColumn]@{
					Id = $sqlReader['ColumnId']
					Name = $sqlReader['ColumnName']
					Order = $sqlReader['Order']
				})
			}
			return $columns
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [Index] GetTableClusteredIndex([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	[name] [Name],
		is_unique [Unique]
from	sys.indexes
where [object_id] = object_id(@ObjectName)
  and [type] = 1
"@

		return [Table]::GetTableIndex($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [Index] GetTablePrimaryKeyIndex([string]$schemaName, [string]$tableName, [SqlConnection]$sqlConnection) {
		$query = @"
select	i.[name] [Name],
		i.is_unique [Unique]
from	sys.key_constraints kc
		join sys.indexes i
		on i.[object_id] = kc.parent_object_id and i.index_id = kc.unique_index_id
where kc.[type] = 'PK'
  and kc.parent_object_id = object_id(@ObjectName)
"@

		return [Table]::GetTableIndex($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [Index] GetTableIndex([string]$query, [string]$objectName, [SqlConnection]$sqlConnection) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@ObjectName", [System.Data.SqlDbType]::NVarChar, 257).Value = $objectName
			$sqlReader = $sqlCmd.ExecuteReader()
			
			if ($sqlReader.Read()) {
				return [Index]@{
					Name = $sqlReader['Name']
					Unique = [bool]$sqlReader['Unique']
				}
			}

			return $null
		}
		finally {
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	CompareColumns() {
		#if ($this.SrcColumns.Count -lt $this.DstColumns.Count) {
		#	Write-LogMessage -Message "The table [$($this.SchemaName)].[$($this.TableName)] schema is not the same on source and destination"
		#	return $false
		#}

		foreach($s in $this.SrcColumns.GetEnumerator() | Select-Object -ExpandProperty Value) {
			$d = $null
			$b = $this.DstColumns.TryGetValue($s.Name, [ref]$d)
			if ($b) {
				if ($d.DataType -ne $s.DataType -or $d.Collation -ne $s.Collation `
					-or $d.Computed -ne $s.Computed `
					-or $d.Nullable -ne $s.Nullable) {
					throw "The column [$($s.Name)] isn't the same in the source and destination table"
				}
			}
			else {
				#Write-LogMessage -Message "The column [$($s.Name)] doesn't exist in the destination table"
				if (-not $s.Computed) {
					$this.MissedColumns.Add($s)
				}
			}
		}
	}

	[bool]AddMissedColumns() {
		if ($this.MissedColumns.Count -eq 0) {
			return $false
		}

		$query = [System.Text.StringBuilder]::new()
		$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add ")

		foreach ($c in $this.MissedColumns) {
			if ([string]::IsNullOrEmpty($c.Collation)) {
				$query.Append("[$($c.Name)] $($c.DataType) null,")
			}
			else {
				$query.Append("[$($c.Name)] $($c.DataType) collate $($c.Collation) null,")
			}
		}
		$query.Length -= 1

		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query.ToString(), $this.Group.DstSqlConn) 
			$sqlCmd.ExecuteNonQuery()

			return $true
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	CreateDestinationTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append("set xact_abort on  begin tran create table [$($this.SchemaName)].[$($this.TableName)](")

		#foreach ($c in $this.SrcColumns.Where({ -not $_.Computed })) {
		foreach ($c in $this.SrcColumns.GetEnumerator() | Select-Object -ExpandProperty Value) {
			$query.Append([Table]::GetColumnDefinition($c) + ',')
			#if ([string]::IsNullOrEmpty($c.Collation)) {
			#	$query.Append("[$($c.Name)] $($c.DataType) ")
			#}
			#else {
			#	$query.Append("[$($c.Name)] $($c.DataType) collate $($c.Collation) ")
			#}
			#if ($c.Nullable) {
			#	$query.Append('null,')
			#}
			#else {
			#	$query.Append('not null,')
			#}
		}
		$query.Length -= 1
		$query.Append(') ')

		#$pk = [Table]::GetTablePrimaryKeyIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		#$cl = [Table]::GetTableClusteredIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)

		if ($this.SrcPk.Name -ne $this.SrcCl.Name) {
			#$columns = [Table]::GetTableClusteredColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
			if ($this.SrcCl.Unique) {
				$query.Append("create unique clustered ")
			}
			else {
				$query.Append("create clustered index ")
			}
			$query.Append("index [$($this.SrcCl.Name)] on [$($this.SchemaName)].[$($this.TableName)] (")
			foreach ($c in $this.SrcClColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1

			$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add constraint $($this.SrcCl.Name) primary key nonclustered (")
			foreach ($c in $this.SrcPkColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1
			$query.Append(') ')
		}
		else {
			$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add constraint $($this.SrcPk.Name) primary key clustered (")
			foreach ($c in $this.SrcPkColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1
			$query.Append(') ')
		}
		$query.Append('commit tran')
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query.ToString(), $this.Group.DstSqlConn) 
			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	CreateDestinationTableSchema() {
		$query = "create schema [$($this.SchemaName)]"
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query, $this.Group.DstSqlConn) 
			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	DisableEnableFK($disable) {
		if (-not $this.Group.DisableFK) {
			return
		}

		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_DisableEnableFK', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.Id
			$pDisable = $sqlCmd.Parameters.Add('@Disable', [System.Data.SqlDbType]::Bit)
			$pDisable.Value = $disable

			$sqlCmd.ExecuteNonQuery()

			$this.FKDisabled = $disable
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	DropWorkingTables() {
		return
		$sqlCmd = $null
		try {
			$query = @"
if exists(	select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.SrcWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.SrcWorkingTableName)]
end

if exists(  select  1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.DstWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.DstWorkingTableName)]
end
"@
			$sqlCmd = [SqlCommand]::new($query, $this.Group.ArcSqlConn)
			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	CreateSourceWorkingTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append(@"
if exists(	select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.SrcWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.SrcWorkingTableName)]
end
create table dbo.[$($this.SrcWorkingTableName)] ([$($this.WorkingTableKeyName)] int identity(1,1) not null primary key clustered, [$($this.WorkingTableFlagName)] bit not null default 0,
"@)

		foreach ($pkc in $this.SrcPkColumns) {
			$c = $null
			$b = $this.SrcColumns.TryGetValue($pkc.Name, [ref]$c)
			if (-not $b) {
				throw "Primary key column [$($pkc.Name)] not found for [$($this.SchemaName)].[$($this.TableName)] table"
			}
			$query.Append([Table]::GetColumnDefinition($c) + ',')
			#if ([string]::IsNullOrEmpty($c.Collation)) {
			#	$query.Append("[$($c.Name)] $($c.DataType) not null,")
			#}
			#else {
			#	$query.Append("[$($c.Name)] $($c.DataType) collate $($c.Collation) not null,")
			#}
		}
		$query.Length -= 1
		$query.Append(')')
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query.ToString(), $this.Group.ArcSqlConn) 
			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	CreateDestinationWorkingTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append(@"
if exists(  select  1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.DstWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.DstWorkingTableName)]
end
create table dbo.[$($this.DstWorkingTableName)] ([$($this.WorkingTableKeyName)] int identity(1,1) not null primary key clustered,
"@)

		foreach ($pkc in $this.SrcPkColumns) {
			$c = $null
			$b = $this.SrcColumns.TryGetValue($pkc.Name, [ref]$c)
			if (-not $b) {
				throw "Primary key column [$($pkc.Name)] not found for [$($this.SchemaName)].[$($this.TableName)] table"
			}
			$query.Append([Table]::GetColumnDefinition($c) + ',')
			#if ([string]::IsNullOrEmpty($c.Collation)) {
			#	$query.Append("[$($c.Name)] $($c.DataType) not null,")
			#}
			#else {
			#	$query.Append("[$($c.Name)] $($c.DataType) collate $($c.Collation) not null,")
			#}
		}
		$query.Length -= 1
		$query.Append(')')
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new($query.ToString(), $this.Group.ArcSqlConn) 
			$sqlCmd.ExecuteNonQuery()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	BulkCopySourcePK() {
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [SqlCommand]::new($this.KeyQuery, $this.Group.SrcSqlConn) 
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$bulkCopy = [SqlBulkCopy]::new($this.Group.ArcSqlConn)

			$bulkCopy.DestinationTableName = $this.SrcWorkingTableName
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.KeyCopyBatchSize
			foreach ($c in $this.SrcPkColumns) {
				[void]$bulkCopy.ColumnMappings.Add([SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($bulkCopy) {
				$bulkCopy.Close()
				$bulkCopy.Dispose()
			}
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	BulkCopyDestinationPK() {
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [SqlCommand]::new($this.KeyQuery, $this.Group.DstSqlConn) 
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$bulkCopy = [SqlBulkCopy]::new($this.Group.ArcSqlConn)

			$bulkCopy.DestinationTableName = $this.DstWorkingTableName
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.KeyCopyBatchSize
			foreach ($c in $this.SrcPkColumns) {
				[void]$bulkCopy.ColumnMappings.Add([SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($bulkCopy) {
				$bulkCopy.Close()
				$bulkCopy.Dispose()
			}
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	BulkCopyTable() {
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [SqlCommand]::new('dbo.stp_GetBulkCopyData', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.State.Id
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$options = [SqlBulkCopyOptions]::KeepIdentity -bor [SqlBulkCopyOptions]::KeepNulls
			$bulkCopy = [SqlBulkCopy]::new($this.Group.DstSqlConn.ConnectionString, $options)

			$bulkCopy.DestinationTableName = "[$($this.SchemaName)].[$($this.TableName)]"
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.NotifyAfter = $this.DataCopyBatchSize / 10
			$localTable = $this
			$bulkCopy.add_SqlRowsCopied({
				param($s, $e)
				$localTable.State.SetRowsCopied($e.RowsCopied)
			})

			foreach ($c in $this.SrcColumns.GetEnumerator() | Select-Object -ExpandProperty Value) {
				if (-not $c.Computed) {
					[void]$bulkCopy.ColumnMappings.Add([SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
				}
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($bulkCopy) {
				$bulkCopy.Close()
				$bulkCopy.Dispose()
			}
			if ($sqlReader) {
				$sqlReader.Close()
				$sqlReader.Dispose()
			}
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	PurgeData() {
		$sqlCmd = $null
		try {
			$sqlCmd = [SqlCommand]::new('dbo.stp_PurgeData', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.State.Id

			$this.State.RowsPurgedForBatch = [int]$sqlCmd.ExecuteScalar()
		}
		finally {
			if ($sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}
}

function Invoke-EasyArchiving {
	Param (
		[parameter(Mandatory)]
		[string]$ConnStr,

		[parameter(Mandatory)]
		[string]$GroupName
	)

	Set-StrictMode -Version Latest

	$group = $null
	try { 
		$group = [TableGroup]::new($ConnStr, $GroupName)
		if ($group.Id -eq 0) {
			throw "Specified table group ($GroupName) not found"
		}
		Write-LogMessage -Message "Archive group ($GroupName) found"

		$group.ReadSourceTables()

		if ($group.SourceTables.Count -eq 0) {
			Write-LogMessage -Message "No tables found for the specified table group ($GroupName)"
			return
		}
		Write-LogMessage -Message "$($group.SourceTables.Count) archive table(s) found"

		foreach ($table in $group.SourceTables) {
			if (-not ($table.IsTableExistsInSource())) {
				throw "Error occurred. The source table [$($table.SchemaName)].[$($table.TableName)] doesn't exist"
			}
			Write-LogMessage -Message "Collecting columns info for source table [$($table.SchemaName)].[$($table.TableName)]"
			$table.ReadSrcTableColumns()
			Write-LogMessage -Message "Columns info collected for source table [$($table.SchemaName)].[$($table.TableName)]"

			if (-not $table.IsTableExistsInDestination()) {
				if (-not $table.IsTableSchemaExistsInDestination()) {
					Write-LogMessage -Message "The destination schema [$($table.SchemaName)] doesn't exist. Trying to create"
					$table.CreateDestinationTableSchema()
				}
				Write-LogMessage -Message "The destination table [$($table.SchemaName)].[$($table.TableName)] doesn't exist. Trying to create"
				$table.CreateDestinationTable()
				Write-LogMessage -Message "The destination table [$($table.SchemaName)].[$($table.TableName)] created"
			}
			else {
				Write-LogMessage -Message "Collecting columns info for destination table [$($table.SchemaName)].[$($table.TableName)]"
				$table.ReadDstTableColumns()
				Write-LogMessage -Message "Columns info collected for destination table [$($table.SchemaName)].[$($table.TableName)]"

				$table.CompareColumns()

				if ($table.AddMissedColumns()) {
					Write-LogMessage -Message "Missed columns added to the [$($table.SchemaName)].[$($table.TableName)] table"
				}
				Write-LogMessage -Message "Schema comparision passed for the table [$($table.SchemaName)].[$($table.TableName)]"
			}

			$table.GetState()
			$copyPK = $true

			# is it incomplete process?
			if ($table.State.IncompleteProcess) {
				Write-LogMessage -Message "Incomplete process found for the table [$($table.SchemaName)].[$($table.TableName)]"

				# KeyCopyDate has value?
				if ($table.State.IsKeysCopied()) {
					$copyPK = $false
				}
			}
			else {
				# Create a new record in ProcessState
				$table.State.Create()
				$copyPK = $true
			}

			if ($copyPK) {
				# Create a working table
				$table.CreateSourceWorkingTable()
				Write-LogMessage -Message "Working table recreated for [$($table.SchemaName)].[$($table.TableName)]"

				# Populate PK values from source and update KeyCopyDate
				Write-LogMessage -Message "PK copy started for the table [$($table.SchemaName)].[$($table.TableName)]"
				$table.BulkCopySourcePK()
				Write-LogMessage -Message "PK values copied for the table [$($table.SchemaName)].[$($table.TableName)]"

				$table.State.UpdateKeyMaxValue()
				$table.State.UpdateKeyCopyDate()
			}

			if ($table.State.IncompleteProcess -or $table.AlwaysRunCheck) {
				$table.CreateDestinationWorkingTable()
				$table.BulkCopyDestinationPK()
				$table.State.FixAndGetLastArchivedKey()
				Write-LogMessage -Message "LastArchivedKey fixed for the table [$($table.SchemaName)].[$($table.TableName)]"
			}
			else {
				$table.State.LastArchivedKey = 0
				$table.State.RowsCopied = 0
				$table.State.UpdateArchiveState()
			}

			Write-LogMessage -Message "Data copy started for the table [$($table.SchemaName)].[$($table.TableName)]"
			while ($table.State.ArchiveProcessHasRowsForNextBatch()) {
				$table.BulkCopyTable()

				$table.State.LastArchivedKey += $table.DataCopyBatchSize
				$table.State.RowsCopied += $table.State.RowsCopiedForBatch
				$table.State.UpdateArchiveState()
				if ($table.State.RowsCopiedForBatch -gt 0) {
					Start-Sleep -Seconds $table.DelayIntervalInSeconds
				}
			}
			$table.State.UpdateArchiveState()
			Write-LogMessage -Message "Data copy completed for the table [$($table.SchemaName)].[$($table.TableName)]"

			if (-not $table.Purge) {
				$table.State.UpdateCompleteDate()
				$table.DropWorkingTables()
			}
		}
		Write-LogMessage -Message "Archive process completed for the group ($($group.Name))"

		# For each table in a group according to PurgeOrder
		$b = $false
		foreach ($table in $group.SourceTables.Where({ $_.Purge }) | Sort-Object -Property PurgeOrder) { 
			if (-not $table.State.IncompleteProcess) {
				$table.State.LastPurgedKey = 0
				$table.State.RowsPurged = 0
				$table.State.UpdatePurgeState()
			}

			Write-LogMessage -Message "Purge started for the table [$($table.SchemaName)].[$($table.TableName)]"
			while ($table.State.PurgeProcessHasRowsForNextBatch()) {
				$table.DisableEnableFK($true)
				$table.PurgeData()
				$table.DisableEnableFK($false)

				$table.State.LastPurgedKey = $table.State.LastPurgedKey + $table.DataCopyBatchSize
				$table.State.RowsPurged = $table.State.RowsPurged + $table.State.RowsPurgedForBatch
				$table.State.UpdatePurgeState()
				Start-Sleep -s $table.DelayIntervalInSeconds
			}
			Write-LogMessage -Message "Purge completed for the table [$($table.SchemaName)].[$($table.TableName)]"

			$table.State.UpdateCompleteDate()
			$table.DropWorkingTables()
			$b = $true
		}
		if ($b) {
			Write-LogMessage -Message "Purge process completed for the group ($($group.Name))"
		}
	}
	catch {
		Write-LogMessage -Message $_.Exception.ToString()
		throw
	}
	finally {
		if ($group) {
			$group.Dispose()
		}
	}
}