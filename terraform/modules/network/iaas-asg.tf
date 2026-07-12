# =====================================================
# IaaS SQL-on-VM track — application security groups + rules
# -----------------------------------------------------
# Two ASGs with different scopes (do not merge them):
#   asg-win-<suffix>  — internet-facing 1433 (Linux + both Windows node NICs);
#                       consumed by Allow-SQL-Engine-Peers (sql-engine-access.sh)
#   asg-sqlcluster    — intra-cluster WSFC ports, ASG-to-ASG on both node NSGs
#                       (cluster-nsg-rules.sh)
#
# Recorded shell defect, fixed here by construction: application-security-
# group.sh and cluster-nsg-rules.sh both call `az network nic ip-config update
# --application-security-groups <one ASG>`, which REPLACES the ip-config's ASG
# list — sequential runs overwrite each other's membership on the Windows NICs
# and oscillate between runs. Both scripts' comments state the intended fixed
# point (memberships coexist), which Terraform's per-pair association
# resources model declaratively: Windows NICs carry BOTH ASGs, Linux carries
# asg-win only.
# =====================================================

resource "azurerm_application_security_group" "iaas_win" {
  count = var.iaas_enabled ? 1 : 0

  name                = "asg-win-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
}

resource "azurerm_application_security_group" "iaas_sqlcluster" {
  count = var.iaas_enabled ? 1 : 0

  name                = "asg-sqlcluster"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
}

# --- asg-win membership: Linux + both Windows nodes (application-security-group.sh:77) ---

resource "azurerm_network_interface_application_security_group_association" "iaas_linux_win_asg" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id          = azurerm_network_interface.iaas_linux[0].id
  application_security_group_id = azurerm_application_security_group.iaas_win[0].id
}

resource "azurerm_network_interface_application_security_group_association" "iaas_win_win_asg" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id          = azurerm_network_interface.iaas_win[0].id
  application_security_group_id = azurerm_application_security_group.iaas_win[0].id
}

resource "azurerm_network_interface_application_security_group_association" "iaas_win2_win_asg" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id          = azurerm_network_interface.iaas_win2[0].id
  application_security_group_id = azurerm_application_security_group.iaas_win[0].id
}

# --- asg-sqlcluster membership: both Windows nodes (cluster-nsg-rules.sh:54) ---

resource "azurerm_network_interface_application_security_group_association" "iaas_win_cluster_asg" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id          = azurerm_network_interface.iaas_win[0].id
  application_security_group_id = azurerm_application_security_group.iaas_sqlcluster[0].id
}

resource "azurerm_network_interface_application_security_group_association" "iaas_win2_cluster_asg" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id          = azurerm_network_interface.iaas_win2[0].id
  application_security_group_id = azurerm_application_security_group.iaas_sqlcluster[0].id
}

# =====================================================
# WSFC intra-cluster rules — ASG-to-ASG on BOTH Windows NSGs
# (cluster-nsg-rules.sh:93-134). Priorities 100-140 sit above the client-IP
# rules (1000+) so cluster traffic is admitted first. 3343 is protocol "*"
# (heartbeat runs over both TCP and UDP).
# =====================================================

locals {
  iaas_cluster_rules = {
    "Allow-WSFC-SQL-1433"       = { priority = 100, protocol = "Tcp", ports = "1433" }
    "Allow-WSFC-HADR-5022"      = { priority = 110, protocol = "Tcp", ports = "5022" }
    "Allow-WSFC-Heartbeat-3343" = { priority = 120, protocol = "*", ports = "3343" }
    "Allow-WSFC-RPC-135"        = { priority = 130, protocol = "Tcp", ports = "135" }
    "Allow-WSFC-DynRPC"         = { priority = 140, protocol = "Tcp", ports = "49152-65535" }
  }

  iaas_cluster_rule_matrix = {
    for pair in setproduct(["win", "win2"], keys(local.iaas_cluster_rules)) :
    "${pair[0]}/${pair[1]}" => {
      nsg      = pair[0]
      name     = pair[1]
      priority = local.iaas_cluster_rules[pair[1]].priority
      protocol = local.iaas_cluster_rules[pair[1]].protocol
      ports    = local.iaas_cluster_rules[pair[1]].ports
    }
  }
}

resource "azurerm_network_security_rule" "iaas_cluster" {
  for_each = var.iaas_enabled ? local.iaas_cluster_rule_matrix : {}

  name      = each.value.name
  priority  = each.value.priority
  direction = "Inbound"
  access    = "Allow"
  protocol  = each.value.protocol

  source_application_security_group_ids      = [azurerm_application_security_group.iaas_sqlcluster[0].id]
  source_port_range                          = "*"
  destination_port_range                     = each.value.ports
  destination_application_security_group_ids = [azurerm_application_security_group.iaas_sqlcluster[0].id]

  resource_group_name         = var.iaas_rg
  network_security_group_name = azurerm_network_security_group.iaas[each.value.nsg].name
}

# =====================================================
# SQL engine peer access — inbound 1433, IP-allowlist source, ASG destination
# (sql-engine-access.sh). Source must be an IP list because peers arrive over
# their PUBLIC IPs (an ASG can never match an internet source); destination is
# the ASG so one rule covers every member NIC. Applied to all three SQL-VM
# NSGs. Priority 1021 sits between Allow-SQL-Client-IP (1020) and
# Allow-LB-Probe (1030). Standard PIPs are Static, so .ip_address is stable.
# =====================================================

resource "azurerm_network_security_rule" "iaas_sql_engine_peers" {
  for_each = var.iaas_enabled ? toset(["linux", "win", "win2"]) : toset([])

  name      = "Allow-SQL-Engine-Peers"
  priority  = 1021
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_address_prefixes = compact([
    var.client_ip,
    azurerm_public_ip.iaas["linux"].ip_address,
    azurerm_public_ip.iaas["win"].ip_address,
    azurerm_public_ip.iaas["win2"].ip_address,
  ])
  source_port_range = "*"

  destination_port_range                     = local.iaas_sql_port
  destination_application_security_group_ids = [azurerm_application_security_group.iaas_win[0].id]

  resource_group_name         = var.iaas_rg
  network_security_group_name = azurerm_network_security_group.iaas[each.key].name
}
