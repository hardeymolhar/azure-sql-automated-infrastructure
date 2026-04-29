USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_password_history]    Script Date: 4/29/2026 9:35:00 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_password_history](
	[id] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[passsword_hash] [nvarchar](255) NULL,
	[user_id] [bigint] NULL,
 CONSTRAINT [PK__tbl_pass__3213E83F56913A7E] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]