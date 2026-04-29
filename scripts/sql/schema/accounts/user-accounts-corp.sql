USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_user_accountsCorp]    Script Date: 4/29/2026 9:39:53 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_user_accountsCorp](
	[id] [int] NOT NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[customer_account_id] [nvarchar](255) NULL,
	[deleted_by] [nvarchar](255) NULL,
	[deleted_on] [datetime2](7) NULL,
	[user_name] [nvarchar](50) NOT NULL
) ON [PRIMARY]