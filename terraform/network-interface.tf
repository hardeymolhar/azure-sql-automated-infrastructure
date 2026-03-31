
# NIC
resource "azurerm_network_interface" "nic" {
  name                = "vm--nic"
  location            = local.primary_location
  resource_group_name = local.primary_rg

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet["dev-vnet-app-subnet"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id

  }
}


# NIC
resource "azurerm_network_interface" "db_nic" {
  name                = "db-nic"
  location            = local.primary_location
  resource_group_name = local.primary_rg

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet["dev-vnet-app-subnet"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.db_vm_pip.id

  }
}



# =====================================================
# VM Public IPs
# =====================================================

resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-linux-vm-eastus"
  location            = local.primary_location
  resource_group_name = local.primary_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}



resource "azurerm_public_ip" "db_vm_pip" {
  name                = "pip-db-vm-eastus"
  location            = local.primary_location
  resource_group_name = local.primary_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}