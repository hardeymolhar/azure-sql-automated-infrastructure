USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_bill_payments]    Script Date: 4/29/2026 9:38:28 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_bill_payments](
	[bill_payment_response] [nvarchar](255) NULL,
	[bill_payment_response_time] [datetime2](7) NULL,
	[customer_id] [nvarchar](255) NULL,
	[payment_code] [nvarchar](255) NULL,
	[payment_reference] [nvarchar](255) NULL,
	[id] [bigint] NOT NULL,
	[OldId] [bigint] NULL,
	[request_reference] [nvarchar](255) NULL,
	[reversedStatus] [varchar](50) NULL,
 CONSTRAINT [PK__tbl_bill__13213E83F85B22BB0] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY]

ALTER TABLE [dbo].[tbl_bill_payments]  WITH NOCHECK ADD  CONSTRAINT [FKnmiimqr2ycxqikc10necrdop1] FOREIGN KEY([id])
REFERENCES [dbo].[tbl_transactions] ([id])

ALTER TABLE [dbo].[tbl_bill_payments] CHECK CONSTRAINT [FKnmiimqr2ycxqikc10necrdop1]