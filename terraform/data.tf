

data "azurerm_client_config" "current" {}

data "http" "client_ip" {
  url = "https://api.ipify.org"
}

data "terraform_remote_state" "storage" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg_sb_westus_308450_2_178362756618"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }


}

