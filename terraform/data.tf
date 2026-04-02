

data "azurerm_client_config" "current" {}

data "http" "client_ip" {
  url = "https://api.ipify.org"
}

data "terraform_remote_state" "storage" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg_sb_westus_308450_2_177514317960"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}





#======
#SAS
#======

data "azurerm_storage_account_sas" "script_sas" {
  connection_string = data.terraform_remote_state.storage.outputs.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "2h")

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    filter  = false
    tag     = false
  }
}

