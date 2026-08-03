# =============================================================================
# NETWORKING — replaces network.sh and private-dns.sh
# -----------------------------------------------------------------------------
# db-deploy.sh STEP 1 and STEP 1b.
#
# Networking is the foundation everything else hangs off, and in the shell
# pipeline that ordering existed only as a comment ("Networking comes FIRST",
# db-deploy.sh:27). Here it is a real dependency graph: the storage account's VNet
# rules reference subnet IDs, the VMs reference NIC IDs, and the private DNS link
# references the VNet ID, so Terraform cannot get the order wrong.
# =============================================================================

# -----------------------------------------------------------------------------
# Virtual network and subnets
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space

  tags = var.tags
}

# The workload subnet. Service endpoints are not decoration: storage.sh registers
# a VNet rule against this subnet, and that rule is rejected by Azure unless
# Microsoft.Storage is enabled here first. In the shell pipeline this was a
# separate `az network vnet subnet update` call whose relationship to the storage
# rule was invisible; here it is one attribute on the resource the rule depends on.
resource "azurerm_subnet" "main" {
  name                 = local.main_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.main_subnet_prefix

  service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
}

# Second Windows subnet. Faithfully reproduced from network.sh:154-173 including
# its oddity: it is created and given a service endpoint, storage.sh registers a
# VNet rule for it, but NO NIC is ever placed in it. Both SQL nodes live in the
# main subnet above. See the note on azurerm_network_interface.win below.
resource "azurerm_subnet" "win" {
  name                 = local.win_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.win_subnet_prefix

  service_endpoints = ["Microsoft.Storage"]
}

# Reserved for a future bastion.sh conversion. The name is mandated by Azure and
# must be exactly "AzureBastionSubnet" with a /26 or larger prefix.
resource "azurerm_subnet" "bastion" {
  count = var.create_bastion_subnet ? 1 : 0

  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.bastion_subnet_prefix
}

# -----------------------------------------------------------------------------
# Network security groups
# -----------------------------------------------------------------------------
# One NSG per Windows node, matching network.sh:184 and :294. They carry identical
# rule sets; separate NSGs exist so a single node can be isolated during incident
# response without touching its peer.
#
# Rules are declared as standalone azurerm_network_security_rule resources rather
# than inline security_rule{} blocks on the NSG. The two forms conflict — using
# both makes every apply fight the previous one, because the NSG resource treats
# any rule it does not know about as drift to be removed.

resource "azurerm_network_security_group" "win" {
  for_each = local.win_nodes

  name                = each.value.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Eight rules from one block: {node1, node2} x {RDP, WinRM-HTTP, WinRM-HTTPS, SQL}.
# Every source is local.client_ip — management access is never opened to the
# internet at large, which is what makes the widened in-guest Windows firewall
# rules in the WinRM bootstrap acceptable (see locals.tf).
resource "azurerm_network_security_rule" "win" {
  for_each = local.win_nsg_rule_matrix

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value.port
  source_address_prefix       = local.client_ip
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = each.value.nsg_name

  depends_on = [azurerm_network_security_group.win]
}

# -----------------------------------------------------------------------------
# Public IPs and NICs
# -----------------------------------------------------------------------------
# Standard SKU + Static allocation, matching network.sh:238 and :344. Static is
# load-bearing here rather than a preference: the SQL server firewall rule
# (database.tf) and the Ansible inventory both reference these addresses, so an
# address that changed on deallocation would silently break both.

resource "azurerm_public_ip" "win" {
  for_each = local.win_nodes

  name                = each.value.pip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [each.value.zone]

  tags = var.tags
}

# NOTE: both NICs attach to azurerm_subnet.main, NOT azurerm_subnet.win. This
# reproduces network.sh:254-261 and :360-367 exactly, and it is a deliberate
# architectural choice rather than an oversight — an Always On availability group
# whose replicas share a single subnet cannot advertise a multi-subnet VNN
# listener, so the listener IP (var.ag_listener_ip) is instead floated across the
# nodes by an internal load balancer inside this one subnet. Moving a node into
# azurerm_subnet.win would invalidate that design.
resource "azurerm_network_interface" "win" {
  for_each = local.win_nodes

  name                = each.value.nic_name
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.win[each.key].id
  }

  tags = var.tags
}

# network.sh attaches the NSG with `az network nic create --network-security-group`,
# i.e. at the NIC level, not the subnet level. Preserved: a subnet-level
# association would also govern any future resource placed in the shared subnet,
# which is a wider blast radius than the script intended.
resource "azurerm_network_interface_security_group_association" "win" {
  for_each = local.win_nodes

  network_interface_id      = azurerm_network_interface.win[each.key].id
  network_security_group_id = azurerm_network_security_group.win[each.key].id
}

# -----------------------------------------------------------------------------
# Linux application VM networking (gated — see var.enable_linux_vm)
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "linux" {
  count = var.enable_linux_vm ? 1 : 0

  name                = "pip-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_network_security_group" "linux" {
  count = var.enable_linux_vm ? 1 : 0

  name                = "nsg-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_network_security_rule" "linux_ssh" {
  count = var.enable_linux_vm ? 1 : 0

  name                        = "Allow-SSH-Client-IP"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = local.client_ip
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.linux[0].name
}

resource "azurerm_network_interface" "linux" {
  count = var.enable_linux_vm ? 1 : 0

  name                = "nic-${local.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.linux[0].id
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "linux" {
  count = var.enable_linux_vm ? 1 : 0

  network_interface_id      = azurerm_network_interface.linux[0].id
  network_security_group_id = azurerm_network_security_group.linux[0].id
}

# -----------------------------------------------------------------------------
# Private DNS — replaces private-dns.sh (db-deploy.sh STEP 1b)
# -----------------------------------------------------------------------------
# There is no Active Directory in this sandbox, so a Windows Server Failover
# Cluster has no AD-integrated DNS to register its cluster name object or the AG
# listener in. A private DNS zone linked to the VNet supplies that name resolution
# instead. This is the enabling decision for the whole workgroup-cluster approach:
# without it, WSFC formation and AG listener binding have nothing to resolve.

resource "azurerm_private_dns_zone" "corp" {
  name                = var.private_dns_zone
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# registration_enabled = true is what makes the two SQL nodes publish their own
# A records automatically when they boot — which is why the shell pipeline never
# had to seed node records by hand, only the two static ones below.
#
# The link name here is simply "<vnet>-link". private-dns.sh:27 built it as
# "$VNET_NAME$RESOURCE_SUFFIX", which resolved to "vnet-stg-ind-49stg-ind-49" — a
# double-substitution artefact of var-config.sh's in-place perl rewriting, not an
# intended name. Deriving names from a variable removes that whole failure mode.
resource "azurerm_private_dns_zone_virtual_network_link" "corp" {
  name                  = "${local.vnet_name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.corp.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = true

  tags = var.tags
}

# aglistener.corp.internal — the address clients connect to. It resolves to the
# internal load balancer's frontend IP, which floats to whichever replica
# currently owns the availability group.
resource "azurerm_private_dns_a_record" "ag_listener" {
  name                = "aglistener"
  zone_name           = azurerm_private_dns_zone.corp.name
  resource_group_name = var.resource_group_name
  ttl                 = 60
  records             = [var.ag_listener_ip]

  tags = var.tags
}

# sqlcluster.corp.internal — the WSFC cluster name object (CNO). Distinct from the
# listener: this is the cluster's own identity, used for cluster administration,
# whereas aglistener is the data path clients use.
resource "azurerm_private_dns_a_record" "wsfc_cluster" {
  name                = "sqlcluster"
  zone_name           = azurerm_private_dns_zone.corp.name
  resource_group_name = var.resource_group_name
  ttl                 = 60
  records             = [var.wsfc_cluster_ip]

  tags = var.tags
}
