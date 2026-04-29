USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_corporate_organizations]    Script Date: 4/29/2026 9:06:58 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_corporate_organizations](
	[id] [bigint] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[corporate_id] [nvarchar](255) NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[deleted_by] [nvarchar](255) NULL,
	[deleted_on] [datetime2](7) NULL,
	[name] [nvarchar](255) NULL,
	[primary_accountid] [nvarchar](255) NULL,
 CONSTRAINT [PK__tbl_corp__3213E83F8C74ACA1] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]