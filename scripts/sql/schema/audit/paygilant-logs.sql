USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_paygilant_logs]    Script Date: 4/29/2026 9:17:05 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_paygilant_logs](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[check_point] [nvarchar](20) NULL,
	[created_on] [datetime2](7) NULL,
	[request_id] [nvarchar](255) NULL,
	[risk_level] [nvarchar](255) NULL,
	[risk_score] [nvarchar](255) NULL,
	[severity] [nvarchar](50) NULL,
	[username] [nvarchar](50) NULL,
	[enforce_auto_block] [nvarchar](10) NULL,
	[auth_challenges] [nvarchar](255) NULL,
	[enforce_auto_challenge] [nvarchar](20) NULL,
PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]