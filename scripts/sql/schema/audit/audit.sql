USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_audit]    Script Date: 4/29/2026 9:14:09 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_audit](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[audit_category] [nvarchar](255) NULL,
	[created_by] [nvarchar](255) NULL,
	[date_created] [datetime2](7) NULL,
	[description] [nvarchar](4000) NULL,
	[session_key] [nvarchar](255) NULL,
	[user_id] [nvarchar](255) NULL,
	[login_failure_reason] [nvarchar](255) NULL,
PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]