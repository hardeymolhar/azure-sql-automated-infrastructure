# =====================================================
# IaaS SQL-on-VM track — core networking (shell parity)
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/network.sh. Two deliberate departures from
# the module's existing PaaS machinery:
#   - NSGs attach at the NIC level (azurerm_network_interface_security_group_
#     association), exactly as `az network nic create --network-security-group`
#     does — NOT at the subnet level like the PaaS subnets.
#   - subnet-win (10.10.2.0/24) is created but no NIC ever uses it; network.sh
#     does the same (both SQL nodes actually sit on subnet-<suffix>,
#     10.10.1.0/24). Kept for strict parity — a recorded quirk, not a bug fix.
# Static private IPs: DC1 10.10.4.4, DC2 10.10.4.5 (first assignable in the DC
# subnet). NIC-level DNS points the DC at itself and the SQL nodes at the DC —
# DC2's NIC deliberately keeps Azure default DNS (network.sh only updates
# nic-dc, nic-win, nic-win2; configure-dc2.yml sets DC2's DNS in-guest).
# =====================================================

locals {
  iaas_sfx       = var.iaas_resource_suffix
  iaas_dc_ip     = "10.10.4.4"
  iaas_dc2_ip    = "10.10.4.5"
  iaas_lb_ip     = "10.10.1.200" # AG listener VIP (LB frontend)
  iaas_wsfc_ip   = "10.10.1.201" # WSFC CNO static IP (in-guest; DNS record only)
  iaas_sql_port  = "1433"
  iaas_probe_prt = "59999"

  iaas_subnets = {
    main = {
      name              = "subnet-${local.iaas_sfx}"
      prefix            = "10.10.1.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    }
    win = { # orphaned by the shell too — strict parity
      name              = "subnet-win-${local.iaas_sfx}"
      prefix            = "10.10.2.0/24"
      service_endpoints = ["Microsoft.Storage"]
    }
    dc = {
      name              = "subnet-dc-${local.iaas_sfx}"
      prefix            = "10.10.4.0/24"
      service_endpoints = []
    }
  }

  iaas_nsgs = {
    linux = "nsg-${local.iaas_sfx}"
    win   = "nsg-win-${local.iaas_sfx}"
    win2  = "nsg2-win-${local.iaas_sfx}"
    dc    = "nsg-dc-${local.iaas_sfx}"
  }

  iaas_pips = {
    linux = "pip-${local.iaas_sfx}"
    win   = "pip-win-${local.iaas_sfx}"
    win2  = "pip-win2-${local.iaas_sfx}"
    dc    = "pip-dc-${local.iaas_sfx}"
    dc2   = "pip-dc2-${local.iaas_sfx}"
  }

  # Base NSG rules, one entry per (nsg, rule) — names/priorities/ports are
  # verbatim from network.sh. source "client" resolves to var.client_ip.
  iaas_base_nsg_rules = {
    "linux/Allow-SSH-Client-IP" = { nsg = "linux", name = "Allow-SSH-Client-IP", priority = 1000, protocol = "Tcp", source = "client", ports = ["22"] }

    "win/Allow-RDP-Client-IP" = { nsg = "win", name = "Allow-RDP-Client-IP", priority = 1000, protocol = "Tcp", source = "client", ports = ["3389"] }
    "win/Allow-WinRM-HTTP"    = { nsg = "win", name = "Allow-WinRM-HTTP", priority = 1010, protocol = "Tcp", source = "client", ports = ["5985"] }
    "win/Allow-WinRM-HTTPS"   = { nsg = "win", name = "Allow-WinRM-HTTPS", priority = 1011, protocol = "Tcp", source = "client", ports = ["5986"] }
    "win/Allow-SQL-Client-IP" = { nsg = "win", name = "Allow-SQL-Client-IP", priority = 1020, protocol = "Tcp", source = "client", ports = ["1433"] }

    "win2/Allow-RDP-Client-IP" = { nsg = "win2", name = "Allow-RDP-Client-IP", priority = 1000, protocol = "Tcp", source = "client", ports = ["3389"] }
    "win2/Allow-WinRM-HTTP"    = { nsg = "win2", name = "Allow-WinRM-HTTP", priority = 1010, protocol = "Tcp", source = "client", ports = ["5985"] }
    "win2/Allow-WinRM-HTTPS"   = { nsg = "win2", name = "Allow-WinRM-HTTPS", priority = 1011, protocol = "Tcp", source = "client", ports = ["5986"] }
    "win2/Allow-SQL-Client-IP" = { nsg = "win2", name = "Allow-SQL-Client-IP", priority = 1020, protocol = "Tcp", source = "client", ports = ["1433"] }

    "dc/Allow-AD-TCP"        = { nsg = "dc", name = "Allow-AD-TCP", priority = 1000, protocol = "Tcp", source = "VirtualNetwork", ports = ["53", "88", "135", "389", "445", "464", "636", "3268", "3269", "49152-65535"] }
    "dc/Allow-AD-UDP"        = { nsg = "dc", name = "Allow-AD-UDP", priority = 1010, protocol = "Udp", source = "VirtualNetwork", ports = ["53", "88", "123", "389", "464"] }
    "dc/Allow-RDP-Client-IP" = { nsg = "dc", name = "Allow-RDP-Client-IP", priority = 1100, protocol = "Tcp", source = "client", ports = ["3389"] }
    "dc/Allow-WinRM"         = { nsg = "dc", name = "Allow-WinRM", priority = 1110, protocol = "Tcp", source = "client", ports = ["5985", "5986"] }
  }
}

# =====================================================
# VNet + subnets (network.sh:29,45,154,169,387)
# =====================================================

resource "azurerm_virtual_network" "iaas" {
  count = var.iaas_enabled ? 1 : 0

  name                = "vnet-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "iaas" {
  for_each = var.iaas_enabled ? local.iaas_subnets : {}

  name                 = each.value.name
  resource_group_name  = var.iaas_rg
  virtual_network_name = azurerm_virtual_network.iaas[0].name
  address_prefixes     = [each.value.prefix]
  service_endpoints    = each.value.service_endpoints
}

# =====================================================
# NSGs + base rules (network.sh:60-86,184-227,289-333,398-450)
# =====================================================

resource "azurerm_network_security_group" "iaas" {
  for_each = var.iaas_enabled ? local.iaas_nsgs : {}

  name                = each.value
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
}

resource "azurerm_network_security_rule" "iaas_base" {
  for_each = var.iaas_enabled ? local.iaas_base_nsg_rules : {}

  name      = each.value.name
  priority  = each.value.priority
  direction = "Inbound"
  access    = "Allow"
  protocol  = each.value.protocol

  source_address_prefix = each.value.source == "client" ? var.client_ip : each.value.source
  source_port_range     = "*"

  destination_port_range  = length(each.value.ports) == 1 ? each.value.ports[0] : null
  destination_port_ranges = length(each.value.ports) > 1 ? each.value.ports : null

  destination_address_prefix = "*"

  resource_group_name         = var.iaas_rg
  network_security_group_name = azurerm_network_security_group.iaas[each.value.nsg].name
}

# =====================================================
# Public IPs (network.sh:97,238,344,461,474)
# =====================================================

resource "azurerm_public_ip" "iaas" {
  for_each = var.iaas_enabled ? local.iaas_pips : {}

  name                = each.value
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}

# =====================================================
# NICs (network.sh:115,254,360,490,506)
# ip_configuration name mirrors the az CLI default ("ipconfig1").
# Both SQL-node NICs sit on the MAIN subnet (10.10.1.0/24), not subnet-win —
# verbatim from network.sh:258/:364.
# =====================================================

resource "azurerm_network_interface" "iaas_linux" {
  count = var.iaas_enabled ? 1 : 0

  name                = "nic-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.iaas["main"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iaas["linux"].id
  }
}

resource "azurerm_network_interface" "iaas_win" {
  count = var.iaas_enabled ? 1 : 0

  name                = "nic-win-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  dns_servers         = [local.iaas_dc_ip] # network.sh:529 — SQL nodes point DNS at the DC

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.iaas["main"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iaas["win"].id
  }
}

resource "azurerm_network_interface" "iaas_win2" {
  count = var.iaas_enabled ? 1 : 0

  name                = "nic-win2-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  dns_servers         = [local.iaas_dc_ip] # network.sh:530

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.iaas["main"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.iaas["win2"].id
  }
}

resource "azurerm_network_interface" "iaas_dc" {
  count = var.iaas_enabled ? 1 : 0

  name                = "nic-dc-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  dns_servers         = [local.iaas_dc_ip] # network.sh:528 — the DC points at itself

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.iaas["dc"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.iaas_dc_ip
    public_ip_address_id          = azurerm_public_ip.iaas["dc"].id
  }
}

resource "azurerm_network_interface" "iaas_dc2" {
  count = var.iaas_enabled ? 1 : 0

  name                = "nic-dc2-${local.iaas_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  # No dns_servers: network.sh leaves nic-dc2 on Azure default DNS.

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.iaas["dc"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.iaas_dc2_ip
    public_ip_address_id          = azurerm_public_ip.iaas["dc2"].id
  }
}

# =====================================================
# NIC-level NSG associations (the shell attaches the NSG at `az network nic
# create`; both DC NICs share the DC NSG)
# =====================================================

resource "azurerm_network_interface_security_group_association" "iaas_linux" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.iaas_linux[0].id
  network_security_group_id = azurerm_network_security_group.iaas["linux"].id
}

resource "azurerm_network_interface_security_group_association" "iaas_win" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.iaas_win[0].id
  network_security_group_id = azurerm_network_security_group.iaas["win"].id
}

resource "azurerm_network_interface_security_group_association" "iaas_win2" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.iaas_win2[0].id
  network_security_group_id = azurerm_network_security_group.iaas["win2"].id
}

resource "azurerm_network_interface_security_group_association" "iaas_dc" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.iaas_dc[0].id
  network_security_group_id = azurerm_network_security_group.iaas["dc"].id
}

resource "azurerm_network_interface_security_group_association" "iaas_dc2" {
  count = var.iaas_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.iaas_dc2[0].id
  network_security_group_id = azurerm_network_security_group.iaas["dc"].id
}
