# -- =====================================================
# -- SQL Server Transactional Replication Configuration
# -- Source  : SQL Server (AdventureWorks)
# -- Target  : Azure SQL Database
# -- Purpose : Near zero-downtime migration
# -- =====================================================
USE [master];
GO

# -- =====================================================
# -- STEP 1: Configure Distributor
# -- =====================================================
-- Configure Distributor
EXEC sp_adddistributor
    @distributor = N'CONTOSO-SRV',
    @password = N'';
GO



# -- Creates the distribution database used by replication
# -- Create Distribution Database

EXEC sp_adddistributiondb
    @database = N'distribution',
    @data_folder = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Data',
    @data_file = N'distribution.MDF',
    @data_file_size = 13,
    @log_folder = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Data',
    @log_file = N'distribution.LDF',
    @log_file_size = 9,
    @min_distretention = 0,
    @max_distretention = 72,
    @history_retention = 48,
    @deletebatchsize_xact = 5000,
    @deletebatchsize_cmd = 2000,
    @security_mode = 1;
GO



# -- Registers the SQL Server publisher with the distributor
# -- Add Distribution Publisher

EXEC sp_adddistpublisher
    @publisher = N'CONTOSO-SRV',
    @distribution_db = N'distribution',
    @security_mode = 1,
    @working_directory = N'C:\REPL',
    @trusted = N'false',
    @thirdparty_flag = 0,
    @publisher_type = N'MSSQLSERVER';
GO



# -- Registers Azure SQL Database as a replication subscriber
# -- Register Azure SQL Database Subscriber

EXEC sp_addsubscriber
    @subscriber = N'contoso.database.windows.net',
    @type = 0,
    @description = N'Azure SQL Database (target)';
GO



# -- Enables transactional replication on AdventureWorks
# -- Enable Database for Publishing

EXEC sp_replicationdboption
    @dbname = N'AdventureWorks',
    @optname = N'publish',
    @value = N'true';
GO



# -- Log Reader Agent moves committed transactions to distribution database
# -- Create Log Reader Agent

EXEC [AdventureWorks].sys.sp_addlogreader_agent
    @publisher_security_mode = 1;
GO



# -- Queue Reader Agent handles queued updating subscriptions
# -- Create Queue Reader Agent

EXEC [AdventureWorks].sys.sp_addqreader_agent
    @frompublisher = 1;
GO







-- =====================================================
-- STEP 2: Create Transactional Publication
-- =====================================================
USE [AdventureWorks];
GO

-- Creates the transactional publication
EXEC sp_addpublication
    @publication = N'REPL-AdventureWorks',
    @description = N'Transactional publication of database ''AdventureWorks'' from Publisher ''CONTOSO-SRV''.',
    @sync_method = N'concurrent',
    @retention = 0,
    @allow_push = N'true',
    @allow_pull = N'true',
    @allow_anonymous = N'true',
    @enabled_for_internet = N'false',
    @snapshot_in_defaultfolder = N'false',
    @alt_snapshot_folder = N'C:\REPL',
    @compress_snapshot = N'true',
    @ftp_port = 21,
    @ftp_login = N'anonymous',
    @allow_subscription_copy = N'false',
    @add_to_active_directory = N'false',
    @repl_freq = N'continuous',
    @status = N'active',
    @independent_agent = N'true',
    @immediate_sync = N'true',
    @allow_sync_tran = N'false',
    @autogen_sync_procs = N'false',
    @allow_queued_tran = N'false',
    @allow_dts = N'false',
    @replicate_ddl = 1,
    @allow_initialize_from_backup = N'false',
    @enabled_for_p2p = N'false',
    @enabled_for_het_sub = N'false';
GO

-- Snapshot Agent generates initial schema and data snapshot
-- Create Snapshot Agent
EXEC sp_addpublication_snapshot
    @publication = N'REPL-AdventureWorks',
    @frequency_type = 1,
    @frequency_interval = 0,
    @frequency_relative_interval = 0,
    @frequency_recurrence_factor = 0,
    @frequency_subday = 0,
    @frequency_subday_interval = 0,
    @active_start_time_of_day = 0,
    @active_end_time_of_day = 235959,
    @active_start_date = 0,
    @active_end_date = 0,
    @publisher_security_mode = 0,
    @publisher_login = N'sqladmin',
    @publisher_password = N'<pwd>';
GO



-- =====================================================
-- STEP 3: Create Publication Article
-- =====================================================
USE [AdventureWorks]
GO

-- Publishes the [Person].[Person] table
EXEC sp_addarticle 
	@publication = N'REPL-AdventureWorks', 
	@article = N'Person', 
	@source_owner = N'Person', 
	@source_object = N'Person',
	@type = N'logbased', 
	@description = N'', 
	@creation_script = N'',
	@pre_creation_cmd = N'drop', 
	@schema_option = 0x000000000803509F, 
	@identityrangemanagementoption = N'none', 
	@destination_table = N'Person',
	@destination_owner = N'Person',
	@status = 24, 
	@vertical_partition = N'false', 
	@ins_cmd = N'CALL [sp_MSins_PersonPerson]', 
	@del_cmd = N'CALL [sp_MSdel_PersonPerson]', 
	@upd_cmd = N'SCALL [sp_MSupd_PersonPerson]'
GO




-- =====================================================
-- STEP 4: Create Subscription
-- =====================================================
USE [AdventureWorks]
GO

-- Creates push subscription to Azure SQL Database
EXEC sp_addsubscription 
	@publication = N'REPL-AdventureWorks', 
	@subscriber = N'contoso.database.windows.net', 
	@destination_db = N'my-db',
	@subscription_type = N'Push',
	@sync_type = N'automatic',
	@article = N'all',
	@update_mode = N'read only', 
	@subscriber_type = 0

-- Creates Distribution Agent responsible for pushing transactions
exec sp_addpushsubscription_agent 
	@publication = N'REPL-AdventureWorks', 
	@subscriber = N'contoso.database.windows.net', 
	@subscriber_db = N'my-db',
	@job_login = null, 
	@job_password = null, 
	@subscriber_security_mode = 0, 
	@subscriber_login = N'sqladmin',
	@subscriber_password = '<pwd>', 
	@frequency_type = 64, 
	@frequency_interval = 1, 
	@frequency_relative_interval = 1, 
	@frequency_recurrence_factor = 0,
	@frequency_subday = 4, 
	@frequency_subday_interval = 5,
	@active_start_time_of_day = 0, 
	@active_end_time_of_day = 235959, 
	@active_start_date = 0, 
	@active_end_date = 0, 
	@dts_package_location = N'Distributor'
GO



-- =====================================================
-- Validation Queries
-- =====================================================

-- Check publications
-- EXEC sp_helppublication;

-- Check subscriptions
-- EXEC sp_helpsubscription;

-- Check replication jobs
-- EXEC msdb.dbo.sp_help_job;
