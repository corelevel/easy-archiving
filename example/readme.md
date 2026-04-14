# Example

This example configuration demonstrates how to archive **StackOverflow2013** data from the *Users* table where *CreationDate <= '2008-08-15'*. In my case the data is copied from a local SQL Server instance to a SQL Server instance running in [Docker](https://www.docker.com), targeting the *tempdb* database.

To run *Easy-Archiving*:
* Create a new *easy-archiving* database on your local SQL Server instance
* Download and restore **StackOverflow2013** database on your local SQL Server. You can get a backup [here](https://www.brentozar.com/archive/2015/10/how-to-download-the-stack-overflow-database-via-bittorrent)
* Set up the schema and sample configuration. Before executing the *data.sql* script, update the *group01* settings (such as server names, username, password, etc.) as needed. Then run scripts in the following order:
    * *schema\tables.sql* - creates the required tables
    * *schema\sprocs.sql* - creates the stored procedures
    * *data.sql* - inserts the sample configuration data
* Execute *archive-StackOverflow2013.ps1* using PowerShell 7.0+
