USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_transactions]    Script Date: 4/29/2026 9:02:48 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_transactions](
	[transaction_sub_type] [nvarchar](31) NOT NULL,
	[id] [bigint] IDENTITY(63264900,1) NOT FOR REPLICATION NOT NULL,
	[amount] [numeric](19, 2) NULL,
	[charged_fee] [float] NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[currency_code] [nvarchar](255) NULL,
	[current_workflow_step] [int] NULL,
	[destination_account_name] [nvarchar](255) NULL,
	[destination_account_number] [nvarchar](255) NULL,
	[destination_bank_code] [nvarchar](255) NULL,
	[transaction_type] [nvarchar](255) NULL,
	[transaction_external_reference] [nvarchar](255) NULL,
	[modified_by] [nvarchar](255) NULL,
	[modified_on] [datetime2](7) NULL,
	[narration] [nvarchar](255) NULL,
	[narration_extended] [nvarchar](255) NULL,
	[reversal_date] [datetime2](7) NULL,
	[reversal_status] [nvarchar](255) NULL,
	[reversed] [bit] NULL,
	[session_key] [nvarchar](255) NULL,
	[source_account_number] [nvarchar](255) NULL,
	[transaction_final_status] [nvarchar](255) NULL,
	[transaction_posting_reference] [nvarchar](255) NULL,
	[transaction_reference] [nvarchar](255) NULL,
	[transaction_request_date] [datetime2](7) NULL,
	[transaction_request_status] [nvarchar](255) NULL,
	[transaction_request_status_code] [nvarchar](255) NULL,
	[transaction_response_date] [datetime2](7) NULL,
	[vat_inclusive] [bit] NULL,
	[user_name] [nvarchar](50) NOT NULL,
	[OldId] [bigint] NULL,
	[batch_id] [nvarchar](255) NULL,
	[destination_bank_name] [nvarchar](255) NULL,
	[misc_data] [nvarchar](2000) NULL,
	[recharge_pin] [nvarchar](255) NULL,
	[any_authorizer_accepted] [nvarchar](10) NULL,
	[is_salary] [bit] NULL,
	[isw_client_reference] [nvarchar](255) NULL,
	[isw_transaction_reference] [nvarchar](255) NULL,
	[bill_payments_type] [nvarchar](255) NULL,
	[electricity_token] [nvarchar](255) NULL,
	[transaction_custom_reference] [nvarchar](255) NULL,
	[purpose] [nvarchar](255) NULL,
	[sort_code] [nvarchar](255) NULL,
	[request_transaction_id] [nvarchar](255) NULL,
	[notification_status] [nvarchar](255) NULL,
 CONSTRAINT [PK__tbl_tran__3213E83FAD45D672111] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[tbl_transactions]  WITH CHECK ADD  CONSTRAINT [FKfcuif1liuf2iqrsy9eqkkl8c2] FOREIGN KEY([batch_id])
REFERENCES [dbo].[tbl_bulk_transactions] ([batch_id])

ALTER TABLE [dbo].[tbl_transactions] CHECK CONSTRAINT [FKfcuif1liuf2iqrsy9eqkkl8c2]

ALTER TABLE [dbo].[tbl_transactions]  WITH NOCHECK ADD  CONSTRAINT [FKolttkfiggmaamtvqk33r097qb] FOREIGN KEY([user_name])
REFERENCES [dbo].[tbl_users] ([username])

ALTER TABLE [dbo].[tbl_transactions] NOCHECK CONSTRAINT [FKolttkfiggmaamtvqk33r097qb]

ALTER TABLE [dbo].[tbl_transactions]  WITH CHECK ADD  CONSTRAINT [FKolttkfiggmaamtvqk33r097qv] FOREIGN KEY([user_name])
REFERENCES [dbo].[tbl_users] ([username])

ALTER TABLE [dbo].[tbl_transactions] CHECK CONSTRAINT [FKolttkfiggmaamtvqk33r097qv]