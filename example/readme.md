# Example

Archiving **StackOverflow2013**

This example configuration demonstrates how to archive data from the *Users* table where *CreationDate <= '2008-08-15'*. In my case the data is copied from a local SQL Server instance to a SQL Server instance running in [Docker](https://www.docker.com), targeting the *tempdb* database.

To run *Easy-Archiving*:
* Create a new *easy-archiving* database on your local SQL Server instance
* Download and restore **StackOverflow2013** database. You can get it [here](https://www.brentozar.com/archive/2015/10/how-to-download-the-stack-overflow-database-via-bittorrent)
* Set up the schema and sample configuration. Run the following scripts in the context of the *easy-archiving* database:
    * *schema\tables.sql* - creates required tables
    * *schema\sprocs.sql* - creates stored procedures
    * *data.sql* - inserts sample configuration data
* Execute *archive-StackOverflow2013.ps1* using PowerShell 7.0+

