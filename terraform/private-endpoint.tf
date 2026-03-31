
# ==================================
# Private Endpoint + DNS For Storage
# ==================================

resource "azurerm_private_endpoint" "storage_pe" {
  name                = "pev-dev-storage"
  resource_group_name = local.primary_rg
  location            = local.primary_location
  subnet_id           = azurerm_subnet.subnet["dev-vnet-pe-subnet"].id

  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = data.terraform_remote_state.storage.outputs.storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "storage-dns-group"

    private_dns_zone_ids = [
      azurerm_private_dns_zone.blob.id
    ]
  }
  depends_on = [
    azurerm_subnet.subnet["dev-vnet-pe-subnet"],
    azurerm_private_dns_zone_virtual_network_link.link
  ]
}


resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.primary_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = "blob-dns-link"
  resource_group_name   = local.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id
}


#===============
# INTERNAL LOCAL
#===============


resource "azurerm_private_dns_zone" "vm_dns" {
  name                = "internal.local"
  resource_group_name = local.primary_rg
}


resource "azurerm_private_dns_zone_virtual_network_link" "vm_dns_link" {
  name                  = "vm-dns-link"
  resource_group_name   = local.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.vm_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id

  registration_enabled = true
}
