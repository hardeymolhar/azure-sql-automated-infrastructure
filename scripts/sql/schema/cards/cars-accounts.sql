USE [postcard]

/****** Object:  Table [dbo].[pc_card_accounts_0]    Script Date: 4/29/2026 10:22:27 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[pc_card_accounts_0](
	[issuer_nr] [int] NOT NULL,
	[pan] [varchar](66) NOT NULL,
	[seq_nr] [varchar](3) NOT NULL,
	[account_id] [varchar](66) NOT NULL,
	[account_type_nominated] [varchar](3) NOT NULL,
	[account_type_qualifier] [int] NOT NULL,
	[last_updated_date] [datetime] NOT NULL,
	[last_updated_user] [varchar](20) NOT NULL,
	[account_type] [varchar](3) NOT NULL,
	[date_deleted] [datetime] NULL,
	[account_nickname] [varchar](28) NULL,
	[extended_fields] [varchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

ALTER TABLE [dbo].[pc_card_accounts_0] ADD  DEFAULT ('NIL') FOR [seq_nr]

ALTER TABLE [dbo].[pc_card_accounts_0] ADD  DEFAULT ('NIL') FOR [account_type]