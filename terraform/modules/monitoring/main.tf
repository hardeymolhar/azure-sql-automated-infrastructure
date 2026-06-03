resource "azurerm_log_analytics_workspace" "law" {
  name                = "cosmos-law"
  location            = var.primary_location
  resource_group_name = var.primary_rg

  sku               = "PerGB2018"
  retention_in_days = 30
}
