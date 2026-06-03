# ========================================
# Monitoring & Logging Outputs
# ========================================

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.name
}

output "log_analytics_workspace_resource_id" {
  description = "Workspace (customer) ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.workspace_id
}

output "log_analytics_retention_days" {
  description = "Retention period in days for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.retention_in_days
}

output "log_analytics_primary_key" {
  description = "Primary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.primary_shared_key
  sensitive   = true
}

output "log_analytics_secondary_key" {
  description = "Secondary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.secondary_shared_key
  sensitive   = true
}
