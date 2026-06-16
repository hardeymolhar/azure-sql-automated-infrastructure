terraform {
  backend "azurerm" {

    resource_group_name  = "rg_sb_westus_308450_2_178068175163"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}
