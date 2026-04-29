USE [postcard]

/****** Object:  Table [dbo].[pc_cards_0]    Script Date: 4/29/2026 10:24:45 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[pc_cards_0](
	[issuer_nr] [int] NOT NULL,
	[pan] [varchar](66) NOT NULL,
	[seq_nr] [char](3) NOT NULL,
	[card_program] [varchar](20) NOT NULL,
	[default_account_type] [char](2) NOT NULL,
	[card_status] [int] NOT NULL,
	[card_custom_state] [int] NULL,
	[expiry_date] [varchar](4) NOT NULL,
	[hold_rsp_code] [char](2) NULL,
	[track2_value] [varchar](72) NULL,
	[track2_value_offset] [int] NULL,
	[pvki_or_pin_length] [int] NULL,
	[pvv_or_pin_offset] [varchar](12) NULL,
	[pvv2_or_pin2_offset] [varchar](12) NULL,
	[validation_data_question] [varchar](136) NULL,
	[validation_data] [varchar](136) NULL,
	[cardholder_rsp_info] [varchar](50) NULL,
	[mailer_destination] [int] NOT NULL,
	[discretionary_data] [varchar](72) NULL,
	[date_issued] [datetime] NULL,
	[date_activated] [datetime] NULL,
	[issuer_reference] [varchar](20) NULL,
	[branch_code] [varchar](10) NULL,
	[last_updated_date] [datetime] NOT NULL,
	[last_updated_user] [varchar](20) NOT NULL,
	[customer_id] [varchar](25) NULL,
	[batch_nr] [int] NULL,
	[company_card] [int] NULL,
	[date_deleted] [datetime] NULL,
	[pvki2_or_pin2_length] [int] NULL,
	[extended_fields] [varchar](max) NULL,
	[expiry_day] [char](2) NULL,
	[from_date] [char](4) NULL,
	[from_day] [char](2) NULL,
	[contactless_disc_data] [varchar](19) NULL,
	[dcvv_key_index] [int] NULL,
	[pan_encrypted] [varchar](72) NULL,
	[expiry_date_time] [datetime] NULL,
	[vip] [int] NOT NULL,
	[vip_lapse_date] [datetime] NULL,
	[abu_state] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

ALTER TABLE [dbo].[pc_cards_0] ADD DEFAULT ('NIL') FOR [seq_nr]

ALTER TABLE [dbo].[pc_cards_0] ADD DEFAULT ('NIL') FOR [expiry_date]

ALTER TABLE [dbo].[pc_cards_0] ADD DEFAULT ((0)) FOR [vip]

ALTER TABLE [dbo].[pc_cards_0] ADD DEFAULT ((1)) FOR [abu_state]