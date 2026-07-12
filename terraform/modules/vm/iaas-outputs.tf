# =====================================================
# IaaS SQL-on-VM track — module outputs (null when iaas_enabled = false)
# =====================================================

output "iaas_vm_ids" {
  description = "IaaS VM ids keyed by role (dc/dc2/sql_node1/sql_node2/linux)."
  value = var.iaas_enabled ? {
    dc        = azurerm_windows_virtual_machine.iaas_dc[0].id
    dc2       = azurerm_windows_virtual_machine.iaas_dc2[0].id
    sql_node1 = azurerm_windows_virtual_machine.iaas_sql_node1[0].id
    sql_node2 = azurerm_windows_virtual_machine.iaas_sql_node2[0].id
    linux     = azurerm_linux_virtual_machine.iaas_linux[0].id
  } : null
}

output "iaas_vm_names" {
  description = "IaaS VM names keyed by role — the names env.conf/vm-config-*.sh resolve at runtime."
  value = var.iaas_enabled ? {
    dc        = azurerm_windows_virtual_machine.iaas_dc[0].name
    dc2       = azurerm_windows_virtual_machine.iaas_dc2[0].name
    sql_node1 = azurerm_windows_virtual_machine.iaas_sql_node1[0].name
    sql_node2 = azurerm_windows_virtual_machine.iaas_sql_node2[0].name
    linux     = azurerm_linux_virtual_machine.iaas_linux[0].name
  } : null
}

output "iaas_vm_principal_ids" {
  description = "System-assigned managed-identity principal ids of the IaaS VMs."
  value = var.iaas_enabled ? {
    dc        = azurerm_windows_virtual_machine.iaas_dc[0].identity[0].principal_id
    dc2       = azurerm_windows_virtual_machine.iaas_dc2[0].identity[0].principal_id
    sql_node1 = azurerm_windows_virtual_machine.iaas_sql_node1[0].identity[0].principal_id
    sql_node2 = azurerm_windows_virtual_machine.iaas_sql_node2[0].identity[0].principal_id
    linux     = azurerm_linux_virtual_machine.iaas_linux[0].identity[0].principal_id
  } : null
}
