USE [ExoSkeleton]

/****** Object:  Table [dbo].[tbl_users]    Script Date: 4/29/2026 9:06:20 AM ******/
SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[tbl_users](
	[user_type] [nvarchar](31) NOT NULL,
	[id] [bigint] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[account_verified_on] [datetime2](7) NULL,
	[created_by] [nvarchar](255) NULL,
	[created_on] [datetime2](7) NULL,
	[email] [nvarchar](255) NULL,
	[enrollment_completed_on] [datetime2](7) NULL,
	[enrollment_status] [nvarchar](255) NULL,
	[full_name] [nvarchar](255) NULL,
	[last_failed_login_date] [datetime2](7) NULL,
	[last_login_date] [datetime2](7) NULL,
	[locked] [bit] NULL,
	[login_count] [int] NULL,
	[login_failed_attempts] [int] NULL,
	[mobile] [nvarchar](255) NULL,
	[modified_by] [nvarchar](255) NULL,
	[modified_on] [datetime2](7) NULL,
	[password_change_required] [bit] NULL,
	[password_created_on] [datetime2](7) NULL,
	[password_hash] [nvarchar](255) NULL,
	[profile_picture] [nvarchar](max) NULL,
	[profile_id] [nvarchar](255) NULL,
	[status] [nvarchar](255) NULL,
	[username] [nvarchar](50) NULL,
	[user_id] [bigint] NULL,
	[failed_pin_attempts] [int] NULL,
	[last_failed_pin_date] [datetime2](7) NULL,
	[last_pin_auth_date] [datetime2](7) NULL,
	[pin] [nvarchar](255) NULL,
	[pin_created_on] [datetime2](7) NULL,
	[device_id] [nvarchar](255) NULL,
	[device_locked_to_profile] [bit] NULL,
	[device_type] [nvarchar](255) NULL,
	[policy_accepted] [varchar](1) NOT NULL,
	[policy_accepted_on] [datetime] NULL,
	[ip_address] [nvarchar](255) NULL,
	[accept_any_authorizer] [nvarchar](255) NULL,
	[exo_id] [bigint] NULL,
	[swift_action_signup] [bit] NULL,
	[swift_action_signup_datetime] [datetime2](7) NULL,
	[machine_id] [nvarchar](255) NULL,
	[web_client] [nvarchar](255) NULL,
	[accept_any_authorizers] [nvarchar](255) NULL,
 CONSTRAINT [PK__tbl_user__3213E83F382FE222] PRIMARY KEY CLUSTERED
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY],
 CONSTRAINT [UK_c190nfu2w5xwvexf9dv08grsq] UNIQUE NONCLUSTERED
(
	[username] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

ALTER TABLE [dbo].[tbl_users] ADD  DEFAULT ((0)) FOR [policy_accepted]

ALTER TABLE [dbo].[tbl_users]  WITH CHECK ADD  CONSTRAINT [FK5yml1a9p4m5rj280e4ph78507] FOREIGN KEY([user_id])
REFERENCES [dbo].[tbl_corporate_organizations] ([id])

ALTER TABLE [dbo].[tbl_users] CHECK CONSTRAINT [FK5yml1a9p4m5rj280e4ph78507]