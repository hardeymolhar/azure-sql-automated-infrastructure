# =====================================================
# IaaS SQL-on-VM track — root outputs (null when disabled)
# =====================================================

output "iaas_infrastructure" {
  description = "Summary of the IaaS SQL-on-VM track: VM names, public IPs, listener VIP, vault and witness storage names. Null until iaas_enabled = true."
  value = var.iaas_enabled ? {
    vm_names             = module.vm.iaas_vm_names
    public_ips           = module.network.iaas_public_ips
    ag_listener_ip       = module.network.iaas_lb_private_ip
    key_vault_name       = module.security.iaas_key_vault_name
    storage_account_name = module.sql.iaas_storage_account_name
  } : null
}
