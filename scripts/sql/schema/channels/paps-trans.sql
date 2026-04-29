USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_paps_transaction]    Script Date: 4/29/2026 9:37:59 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_paps_transaction](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[amount] [numeric](19, 2) NULL,
	[amount_rate] [nvarchar](255) NULL,
	[calculated_amount] [numeric](19, 2) NULL,
	[currency_code] [nvarchar](255) NULL,
	[destination_acct] [nvarchar](255) NULL,
	[destination_name] [nvarchar](255) NULL,
	[inserted_at] [datetime2](7) NULL,
	[session_id] [nvarchar](255) NULL,
	[source_acct] [nvarchar](255) NULL,
	[status] [nvarchar](255) NULL,
	[status_code] [nvarchar](255) NULL,
	[transaction_id] [bigint] NULL,
	[updated_at] [datetime2](7) NULL,
	[username] [nvarchar](255) NULL,
	[amount_in_usd] [numeric](19, 2) NULL,
	[amount_in_usd_rate] [numeric](19, 2) NULL,
	[user_name] [nvarchar](255) NULL,
PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]