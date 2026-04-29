USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_bulk_transactions]    Script Date: 4/29/2026 9:10:14 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_bulk_transactions](
	[id] [bigint] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[batch_id] [nvarchar](255) NOT NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[number_of_transactions] [int] NOT NULL,
	[total_transaction_amount] [numeric](19, 2) NULL,
	[debit_method] [nvarchar](255) NULL,
	[number_of_pending_status] [int] NOT NULL,
	[profectus_batch_id] [nvarchar](255) NULL,
	[source_account] [nvarchar](255) NULL,
	[status] [nvarchar](255) NULL,
	[currency_code] [nvarchar](255) NULL,
	[fee] [numeric](19, 2) NULL,
	[current_workflow_step] [int] NOT NULL,
	[narration] [varchar](255) NULL,
	[amount__approved] [numeric](19, 2) NULL,
	[total_transaction_amount_approved] [numeric](19, 2) NULL,
	[batch_posting_status] [nvarchar](255) NULL,
	[commission] [numeric](19, 2) NULL,
	[narration_prefix] [nvarchar](255) NULL,
	[pended_by] [nvarchar](255) NULL,
	[pended_on] [datetime2](7) NULL,
	[sender_name] [nvarchar](255) NULL,
	[total_transaction_amount_pended] [numeric](19, 2) NULL,
	[vat] [numeric](19, 2) NULL,
	[number_of_approved_transaction] [int] NULL,
	[suspense_account] [varchar](200) NULL,
	[approved_on] [datetime2](7) NULL,
	[hasPosted] [bit] NULL,
	[name_enquiry_status] [nvarchar](255) NULL,
	[fraud_sniper_id] [nvarchar](255) NULL,
	[Bulk_ConnectorId] [int] NOT NULL,
 CONSTRAINT [PK__tbl_bulk__3213E83F97429FF5] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY],
 CONSTRAINT [UK_1i339thkyi1fvdqfed3wm911w] UNIQUE NONCLUSTERED
(
	[batch_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[tbl_bulk_transactions] ADD  DEFAULT ((0)) FOR [number_of_approved_transaction]

ALTER TABLE [dbo].[tbl_bulk_transactions] ADD  CONSTRAINT [DF_tbl_bulk_transactions_Bulk_ConnectorId]  DEFAULT (abs(checksum(newid()))%(6)) FOR [Bulk_ConnectorId]