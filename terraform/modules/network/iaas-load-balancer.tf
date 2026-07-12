# =====================================================
# IaaS SQL-on-VM track — internal LB for the Always On AG listener
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/load-balancer.sh. A single-subnet AG cannot
# advertise a multi-subnet VNN listener, so this Standard internal LB owns the
# listener's floating IP (10.10.1.200) and a TCP health probe on 59999 tells it
# which replica currently holds the AG. The frontend is zone-redundant by
# default (Standard SKU) — correct for the zonal nodes. Floating IP is
# immutable after creation, so it is set here at create time.
# The paired NSG rules (Allow-LB-Probe / Allow-AG-Listener-VNet) go on BOTH
# Windows node NSGs — without them the AzureLoadBalancer-sourced probe is
# dropped and the listener silently fails (load-balancer.sh:240-249).
# =====================================================

resource "azurerm_lb" "iaas_sql" {
  count = var.iaas_enabled ? 1 : 0

  name                = "sql-lb-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "sql-listener"
    subnet_id                     = azurerm_subnet.iaas["main"].id
    private_ip_address            = local.iaas_lb_ip
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_lb_backend_address_pool" "iaas_sql_ag" {
  count = var.iaas_enabled ? 1 : 0

  loadbalancer_id = azurerm_lb.iaas_sql[0].id
  name            = "sql-ag-backend-pool"
}

# `az network lb create` without --backend-pool-name also creates a default
# pool named "<lb-name>bepool" (load-balancer.sh:147 omits the flag). It is
# empty and unreferenced — every membership and the LB rule use
# sql-ag-backend-pool — but it is part of the shell's deployed end state, so
# strict parity reproduces it.
resource "azurerm_lb_backend_address_pool" "iaas_default" {
  count = var.iaas_enabled ? 1 : 0

  loadbalancer_id = azurerm_lb.iaas_sql[0].id
  name            = "sql-lb-${local.iaas_sfx}bepool"
}

resource "azurerm_network_interface_backend_address_pool_association" "iaas_win" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id    = azurerm_network_interface.iaas_win[0].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.iaas_sql_ag[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "iaas_win2" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id    = azurerm_network_interface.iaas_win2[0].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.iaas_sql_ag[0].id
}

resource "azurerm_lb_probe" "iaas_sql_ag" {
  count = var.iaas_enabled ? 1 : 0

  loadbalancer_id     = azurerm_lb.iaas_sql[0].id
  name                = "sql-ag-probe"
  protocol            = "Tcp"
  port                = tonumber(local.iaas_probe_prt)
  interval_in_seconds = 5
  probe_threshold     = 2
}

resource "azurerm_lb_rule" "iaas_sql_ag" {
  count = var.iaas_enabled ? 1 : 0

  loadbalancer_id                = azurerm_lb.iaas_sql[0].id
  name                           = "sql-ag-rule"
  protocol                       = "Tcp"
  frontend_port                  = tonumber(local.iaas_sql_port)
  backend_port                   = tonumber(local.iaas_sql_port)
  frontend_ip_configuration_name = "sql-listener"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.iaas_sql_ag[0].id]
  probe_id                       = azurerm_lb_probe.iaas_sql_ag[0].id
  floating_ip_enabled            = true
  tcp_reset_enabled              = true
  idle_timeout_in_minutes        = 30
}

# Listener NSG rules on both Windows node NSGs (load-balancer.sh:251-287).
locals {
  iaas_lb_nsg_rules = {
    "win/Allow-LB-Probe"          = { nsg = "win", name = "Allow-LB-Probe", priority = 1030, source = "AzureLoadBalancer" }
    "win/Allow-AG-Listener-VNet"  = { nsg = "win", name = "Allow-AG-Listener-VNet", priority = 1040, source = "VirtualNetwork" }
    "win2/Allow-LB-Probe"         = { nsg = "win2", name = "Allow-LB-Probe", priority = 1030, source = "AzureLoadBalancer" }
    "win2/Allow-AG-Listener-VNet" = { nsg = "win2", name = "Allow-AG-Listener-VNet", priority = 1040, source = "VirtualNetwork" }
  }
}

resource "azurerm_network_security_rule" "iaas_lb" {
  for_each = var.iaas_enabled ? local.iaas_lb_nsg_rules : {}

  name      = each.value.name
  priority  = each.value.priority
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_address_prefix = each.value.source
  source_port_range     = "*"

  destination_port_ranges    = [local.iaas_sql_port, local.iaas_probe_prt]
  destination_address_prefix = "*"

  resource_group_name         = var.iaas_rg
  network_security_group_name = azurerm_network_security_group.iaas[each.value.nsg].name
}
