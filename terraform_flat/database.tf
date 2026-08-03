# =============================================================================
# PHASE 5 — AZURE SQL DATABASE (PaaS track)
# -----------------------------------------------------------------------------
# db-deploy.sh STEPs 13, 14, 15, 17 and 18. Observability (STEPs 15's workspace,
# 16 and 19) lives in monitoring.tf.
#
#   STEP 13  sql-db.sh              -> server, firewall rules, database, TDE
#   STEP 14  set-entra-admin.sh     -> azuread_administrator block
#   STEP 15  sql-auditing.sh        -> server + database extended auditing
#   STEP 17  sqldb-backup.sh        -> short-term + long-term retention policies
#   STEP 18  sql-automatic-tuning.sh-> ESCAPE HATCH (no azurerm resource)
#
# The whole phase is gated on var.enable_phase5_sql so the IaaS substrate can be
# deployed on its own.
#
# ORDERING the shell scripts encoded in prose and `sleep`, now encoded in the graph:
# the SQL server's managed identity must exist and have propagated before it can be
# granted Key Vault access, and that grant must land before the TDE protector can
# be pointed at the customer-managed key. sql-db.sh:185 waited with `sleep 30`.
# =============================================================================

resource "azurerm_mssql_server" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  name                = local.sql_server_name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "12.0"

  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password

  minimum_tls_version = "1.2"

  identity {
    type = "SystemAssigned"
  }

  # STEP 14 (set-entra-admin.sh). Conditional because the UPN cannot be derived
  # from data.azurerm_client_config — it exposes object_id and tenant_id but not
  # userPrincipalName, and resolving that would need the azuread provider, which is
  # not in this repo's lock file. So it is an explicit input; leave
  # var.entra_admin_login empty to skip it.
  #
  # azuread_authentication_only is deliberately false: setting it true would
  # disable the `sqladmin` SQL login that the firewall rules, identity.sh and the
  # .NET workload simulator all authenticate with.
  dynamic "azuread_administrator" {
    for_each = var.entra_admin_login != "" ? [1] : []

    content {
      login_username              = var.entra_admin_login
      object_id                   = local.entra_admin_object_id
      tenant_id                   = data.azurerm_client_config.current.tenant_id
      azuread_authentication_only = false
    }
  }

  tags = var.tags

  # The TDE protector is owned by azurerm_mssql_server_transparent_data_encryption
  # below, NOT by this resource — but azurerm_mssql_server also exposes an optional
  # transparent_data_encryption_key_vault_key_id, and refresh reads the live key ID
  # back into it. Since the config never sets it, Terraform plans to null it out, and
  # the provider's update path then tries to parse "" as a Key Vault key ID:
  #   Error: expected 2 or 3 path segments, found 1 segment(s) in ``
  # Every apply after the first one failed on that, on this resource.
  #
  # This is HashiCorp's documented pattern for the split-resource layout, not a local
  # workaround: the official azurerm_mssql_server_transparent_data_encryption example
  # carries the same lifecycle block for the same reason.
  #
  # Inlining the key on this resource instead is NOT an option. The chain is
  # server -> system-assigned identity -> azurerm_key_vault_access_policy.sql (which
  # reads identity[0].principal_id) -> TDE protector. Setting the protector here would
  # need depends_on the access policy, which already depends on this server — a cycle.
  # Without the depends_on, Azure rejects the protector before the identity has
  # wrap/unwrap rights, which is exactly what sql-db.sh:185 masked with `sleep 30`.
  #
  # Accepted cost: drift in the TDE protector caused OUTSIDE Terraform is no longer
  # detected. Scoped to this one attribute, not the resource.
  lifecycle {
    ignore_changes = [transparent_data_encryption_key_vault_key_id]
  }
}

# -----------------------------------------------------------------------------
# Firewall rules — sql-db.sh STEP 2 and STEP 2b
# -----------------------------------------------------------------------------
# sql-db.sh created exactly two rules: AllowMyIP (the operator's client IP) and
# AllowVMIP (the Linux VM's public IP). Since the Linux track is gated off by
# default here, that second rule is generalised to one rule per live VM public IP
# — both Windows nodes, plus the Linux VM when enabled.
#
# This is a deliberate improvement over a strict port, not an accident: the
# original would have produced a SQL server that the Windows SQL nodes could not
# reach, because it only ever allowed the Linux VM.
resource "azurerm_mssql_firewall_rule" "allow" {
  for_each = var.enable_phase5_sql ? merge(
    { "AllowMyIP" = local.client_ip },
    { for k, v in azurerm_public_ip.win : "AllowVMIP-${k}" => v.ip_address },
    var.enable_linux_vm ? { "AllowVMIP-linux" = azurerm_public_ip.linux[0].ip_address } : {},
    # "Allow Azure services and resources to access this server" — the portal toggle's exact
    # mechanism (Microsoft Learn: firewall-configure#server-level-versus-database-level-ip-firewall-rules).
    # Authentication is still required; only the network-level check is relaxed to any Azure-internal caller.
    { "AllowAllWindowsAzureIps" = "0.0.0.0" },
  ) : {}

  name             = each.key
  server_id        = azurerm_mssql_server.main[0].id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# -----------------------------------------------------------------------------
# Database — sql-db.sh STEP 3, plus STEP 17's retention policies
# -----------------------------------------------------------------------------
resource "azurerm_mssql_database" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  name      = var.sql_database_name
  server_id = azurerm_mssql_server.main[0].id

  sku_name    = var.sql_database_sku
  max_size_gb = var.sql_database_max_size_gb

  # STEP 17 (sqldb-backup.sh:31-36). Point-in-time restore window.
  short_term_retention_policy {
    retention_days           = var.backup_short_term_retention_days
    backup_interval_in_hours = var.backup_diff_interval_hours
  }

  # STEP 17 (sqldb-backup.sh:45-52). Long-term retention for the compliance
  # requirement a banking workload carries: 12 weekly, 12 monthly, 7 yearly
  # backups, with the yearly backup taken from week 26.
  long_term_retention_policy {
    weekly_retention  = var.backup_ltr.weekly
    monthly_retention = var.backup_ltr.monthly
    yearly_retention  = var.backup_ltr.yearly
    week_of_year      = var.backup_ltr.week_of_year
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Transparent Data Encryption with a customer-managed key — sql-db.sh STEPs 5-7
# -----------------------------------------------------------------------------
# The SQL server's managed identity must be able to wrap and unwrap the TDE
# protector in Key Vault. sql-db.sh did this as `az keyvault set-policy` followed
# by `sleep 30` and then `az sql server key create` + `tde-key set`.
resource "time_sleep" "wait_for_sql_identity" {
  count = var.enable_phase5_sql ? 1 : 0

  create_duration = var.identity_propagation_delay

  triggers = {
    server_id = azurerm_mssql_server.main[0].id
  }
}

resource "azurerm_key_vault_access_policy" "sql" {
  count = var.enable_phase5_sql ? 1 : 0

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_mssql_server.main[0].identity[0].tenant_id
  object_id    = azurerm_mssql_server.main[0].identity[0].principal_id

  key_permissions = ["Get", "WrapKey", "UnwrapKey"]

  depends_on = [time_sleep.wait_for_sql_identity]
}

# Replaces the TDE protector with the customer-managed key. Until this applies,
# the database is encrypted with a Microsoft-managed key; afterwards, revoking the
# Key Vault key renders the database unreadable — which is the point of CMK, and
# also the operational risk it carries.
resource "azurerm_mssql_server_transparent_data_encryption" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  server_id        = azurerm_mssql_server.main[0].id
  key_vault_key_id = azurerm_key_vault_key.tde.id

  depends_on = [azurerm_key_vault_access_policy.sql]
}

# -----------------------------------------------------------------------------
# STEP 15 — Auditing (sql-auditing.sh)
# -----------------------------------------------------------------------------
# Audit records go to Log Analytics rather than to blob storage. That is a
# deliberate difference in kind: blob audit files must be downloaded and opened in
# SSMS, whereas Log Analytics makes them queryable with KQL and joinable against
# the diagnostic telemetry in monitoring.tf — which is what makes an audit
# actually usable during an incident.

# Server-level policy. It carries ALL FIVE audit action groups — the two
# authentication groups sql-auditing.sh:56-65 set on the server, PLUS the three
# data-access groups it set on the database (sql-auditing.sh:68-79).
#
# WHY THE THREE DATABASE GROUPS MOVED UP HERE: azurerm 4.75.0's
# azurerm_mssql_database_extended_auditing_policy has NO audit_actions_and_groups
# attribute — verified against the provider binary, its full schema is
# {database_id, enabled, log_monitoring_enabled, retention_in_days, storage_*}.
# Only the server-level resource accepts action groups.
#
# This loses nothing. Server-level audit action groups apply to every database on
# the server, so the audit coverage is identical to what the two az CLI calls
# produced — it is expressed in one place instead of two.
#
# The coverage, and why each group is here:
#   SUCCESSFUL/FAILED_DATABASE_AUTHENTICATION_GROUP — who connected, and who tried
#     and failed. The first question in any security investigation.
#   SCHEMA_OBJECT_ACCESS_GROUP        — what data was read.
#   DATABASE_OBJECT_CHANGE_GROUP      — what schema was altered.
#   DATABASE_PERMISSION_CHANGE_GROUP  — who was granted what. Privilege escalation
#     is invisible without this one.
resource "azurerm_mssql_server_extended_auditing_policy" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  server_id              = azurerm_mssql_server.main[0].id
  log_monitoring_enabled = true
  retention_in_days      = var.log_retention_days

  audit_actions_and_groups = [
    "SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP",
    "FAILED_DATABASE_AUTHENTICATION_GROUP",
    "SCHEMA_OBJECT_ACCESS_GROUP",
    "DATABASE_OBJECT_CHANGE_GROUP",
    "DATABASE_PERMISSION_CHANGE_GROUP",
  ]

  depends_on = [azurerm_log_analytics_workspace.main]
}

# Database-scoped audit stream, preserved from sql-auditing.sh:68-79. The action
# groups it used are on the server policy above (see the note there); what this
# resource still contributes is a database-scoped audit record with its own
# retention, which survives independently of the server policy.
resource "azurerm_mssql_database_extended_auditing_policy" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  database_id            = azurerm_mssql_database.main[0].id
  log_monitoring_enabled = true
  retention_in_days      = var.log_retention_days

  depends_on = [azurerm_log_analytics_workspace.main]
}

# -----------------------------------------------------------------------------
# STEP 18 — Automatic tuning: ESCAPE HATCH
# -----------------------------------------------------------------------------
# GAP: azurerm 4.75.0 has NO resource for Azure SQL automatic tuning. Verified by
# enumerating every resource schema in the provider binary.
#
# Be clear about what this shim does and does not cover. sql-automatic-tuning.sh
# is two different things:
#   1. an ARM control-plane setting (Microsoft.Sql/.../automaticTuning/current)
#   2. a set of T-SQL statements run through sqlcmd — ALTER DATABASE ... SET
#      QUERY_STORE, SET AUTOMATIC_TUNING(...)
# This resource covers ONLY (1). The T-SQL half is genuinely outside what any IaC
# tool models, and remains the job of the post-apply script — which outputs.tf
# feeds with sql_server_name, sql_database_name and resource_group_name.
#
# As with the storage shim: ordering is graph-managed, but the setting is not in
# state, so Terraform will never report drift on it.
resource "terraform_data" "sql_automatic_tuning" {
  count = var.enable_phase5_sql && var.enable_cli_shims ? 1 : 0

  triggers_replace = [
    azurerm_mssql_database.main[0].id,
    var.sql_automatic_tuning_mode,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      az rest --method PATCH \
        --url "https://management.azure.com${azurerm_mssql_database.main[0].id}/automaticTuning/current?api-version=2021-11-01-preview" \
        --body '{"properties":{"desiredState":"${var.sql_automatic_tuning_mode}"}}' \
        --output none
    EOT
  }

  depends_on = [azurerm_mssql_database.main]
}
