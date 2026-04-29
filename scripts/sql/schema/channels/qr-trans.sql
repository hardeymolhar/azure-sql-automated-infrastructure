USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_qr_transactions]    Script Date: 4/29/2026 9:37:31 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_qr_transactions](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[amount] [nvarchar](255) NULL,
	[creation_date] [nvarchar](255) NULL,
	[machno] [nvarchar](255) NULL,
	[serial_no_response] [nvarchar](255) NULL,
	[submachno] [nvarchar](255) NULL,
	[username] [nvarchar](255) NULL,
PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]