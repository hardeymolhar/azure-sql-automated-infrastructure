terraform {
  backend "azurerm" {

    resource_group_name  = "rg_sb_centralindia_308450_3_177543369631"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "azuresql.tfstate"
  }
}
