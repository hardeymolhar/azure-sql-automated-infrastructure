terraform {
  backend "azurerm" {
    resource_group_name  = "rg_sb_eastus_308450_1_178559957781"
    storage_account_name = "dp300mq"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}
