USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_user_accounts]    Script Date: 4/29/2026 9:09:11 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_user_accounts](
	[id] [int] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[customer_account_id] [nvarchar](255) NULL,
	[deleted_by] [nvarchar](255) NULL,
	[deleted_on] [datetime2](7) NULL,
	[user_name] [nvarchar](50) NOT NULL,
 CONSTRAINT [PK__tbl_user__3213E83F7E380F6E] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[tbl_user_accounts]  WITH NOCHECK ADD  CONSTRAINT [FKll2817yh5mjdrmjw9mfpx2rp3] FOREIGN KEY([user_name])
REFERENCES [dbo].[tbl_users] ([username])

ALTER TABLE [dbo].[tbl_user_accounts] NOCHECK CONSTRAINT [FKll2817yh5mjdrmjw9mfpx2rp3]