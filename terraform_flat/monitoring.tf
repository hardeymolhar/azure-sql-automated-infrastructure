# =============================================================================
# PHASE 5 OBSERVABILITY — replaces diag-settings.sh and sql-alert.sh, plus the
#                         Log Analytics workspace sql-auditing.sh creates
# -----------------------------------------------------------------------------
# db-deploy.sh STEPs 15 (workspace), 16 and 19.
#
# Split out of database.tf so each file holds one concern: database.tf owns the
# data estate and its protection, this file owns how the estate is observed.
#
# The three layers, and why all three exist:
#   AUDIT (database.tf)  — who did what. A security and compliance record.
#   DIAGNOSTICS (here)   — how the engine behaved. Deadlocks, timeouts, waits,
#                          query store statistics. A performance record.
#   ALERTS (here)        — when a human needs to be woken up.
# Auditing without diagnostics cannot explain a slowdown; diagnostics without
# alerts means nobody finds out until a user complains.
# =============================================================================

# Shared destination for both the audit stream (database.tf) and the diagnostic
# stream below. One workspace rather than two, so an investigator can join
# "who connected" against "what the engine was doing" in a single KQL query.
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_phase5_sql ? 1 : 0

  name                = var.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# -----------------------------------------------------------------------------
# STEP 16 — Diagnostic settings (diag-settings.sh:95-143)
# -----------------------------------------------------------------------------
# All nine log categories the script enabled, plus all three metric categories.
#
# "all three", not "AllMetrics": that name is a portal shorthand with no equivalent
# in the API for this resource type — see local.sql_diagnostic_metric_categories for
# what declaring it cost.
#
# log_analytics_destination_type = "Dedicated" is the Terraform spelling of the
# script's `--export-to-resource-specific true`. It matters: without it every
# category lands in the single generic AzureDiagnostics table, where columns are
# shared across every Azure service and quickly hit that table's column limit.
# "Dedicated" gives each category its own strongly-typed table
# (AzureDiagnostics -> SQLInsights, SQLSecurityAuditEvents, ...), which is both
# cheaper to query and far more readable.
resource "azurerm_monitor_diagnostic_setting" "sql_database" {
  count = var.enable_phase5_sql ? 1 : 0

  name                           = local.diag_setting_name
  target_resource_id             = azurerm_mssql_database.main[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main[0].id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = local.sql_diagnostic_log_categories

    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = local.sql_diagnostic_metric_categories

    content {
      category = enabled_metric.value
    }
  }
}

# -----------------------------------------------------------------------------
# STEP 19 — Alerting (sql-alert.sh)
# -----------------------------------------------------------------------------

# Single notification target for every alert below. Centralising it means adding
# a second on-call channel later is one change, not six.
resource "azurerm_monitor_action_group" "sql" {
  count = var.enable_phase5_sql ? 1 : 0

  name                = local.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = "sqlalerts"

  email_receiver {
    name          = "sql-admin-alerts"
    email_address = var.alert_email
  }

  tags = var.tags
}

# Six metric alerts from one block, driven by local.sql_metric_alerts.
#
# Every alert evaluates a 5-minute window every 1 minute. That overlap is
# deliberate: a 5-minute window smooths the spikes a 1-minute window would fire
# on, while the 1-minute frequency keeps detection latency low. A saturation
# signal that alerts on a single bad minute is an alert people learn to ignore.
#
# NOTE the ISO-8601 durations. The az CLI accepted "5m"/"1m"; the ARM API and
# therefore the provider require "PT5M"/"PT1M". This is a silent conversion trap.
#
# Severities are not uniform. Five of the six are saturation signals (severity 2 —
# the workload is under pressure). The deadlock alert is severity 1, because a
# deadlock is a correctness event: transactions are being killed and application
# work is being lost, which is a different class of problem from "CPU is high".
resource "azurerm_monitor_metric_alert" "sql" {
  for_each = var.enable_phase5_sql ? local.sql_metric_alerts : {}

  name                = each.value.name
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_mssql_database.main[0].id]
  description         = each.value.description
  severity            = each.value.severity

  window_size = "PT5M"
  frequency   = "PT1M"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = "GreaterThan"
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.sql[0].id
  }

  tags = var.tags
}
