# =====================================================
# IaaS SQL-on-VM track — private DNS zone corp.internal
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/private-dns.sh. Record strategy is a hybrid:
# node VM A records auto-register via the registration-enabled VNet link the
# moment each Windows node boots; aglistener (ILB VIP) and sqlcluster (WSFC
# CNO) are not VMs, so they are seeded here from the static IPs.
# corp.internal is deliberately DISTINCT from the AD domain (sqlfci.local) —
# the DC's AD-integrated DNS forwards everything else to the Azure resolver
# (168.63.129.16), which resolves this zone.
# The link name concatenates the vnet name and the suffix with no separator
# ("vnet-<sfx><sfx>") — verbatim from private-dns.sh:27 (VNET_LINK_NAME);
# a recorded quirk kept so re-runs of the shell scripts stay idempotent
# against Terraform-built infrastructure.
# =====================================================

resource "azurerm_private_dns_zone" "iaas_corp" {
  count = var.iaas_enabled ? 1 : 0

  name                = "corp.internal"
  resource_group_name = var.iaas_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "iaas_corp" {
  count = var.iaas_enabled ? 1 : 0

  name                  = "vnet-${local.iaas_sfx}${local.iaas_sfx}"
  resource_group_name   = var.iaas_rg
  private_dns_zone_name = azurerm_private_dns_zone.iaas_corp[0].name
  virtual_network_id    = azurerm_virtual_network.iaas[0].id

  registration_enabled = true
}

resource "azurerm_private_dns_a_record" "iaas_aglistener" {
  count = var.iaas_enabled ? 1 : 0

  name                = "aglistener"
  zone_name           = azurerm_private_dns_zone.iaas_corp[0].name
  resource_group_name = var.iaas_rg
  ttl                 = 60
  records             = [local.iaas_lb_ip]
}

resource "azurerm_private_dns_a_record" "iaas_sqlcluster" {
  count = var.iaas_enabled ? 1 : 0

  name                = "sqlcluster"
  zone_name           = azurerm_private_dns_zone.iaas_corp[0].name
  resource_group_name = var.iaas_rg
  ttl                 = 60
  records             = [local.iaas_wsfc_ip]
}
