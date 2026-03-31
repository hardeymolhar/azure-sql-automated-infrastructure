subscription_id = "4f6a6eb9-27d0-4ed6-a31c-2bde135e2db6"


rg = ["rg_sb_eastus_308450_1_177492925587",
  "rg_sb_westus_308450_2_177492925687",
"rg_sb_centralindia_308450_3_177492925857"]

location = ["eastus", "westus", "centralindia"]

admin_password = "r3P1iKa5x_123"



network_structure = {

  dev-vnet = {
    address_space = ["10.1.0.0/16"]

    subnets = {
      app-subnet = {
        address_prefix = ["10.1.1.0/24"]
      }

      db-subnet = {
        address_prefix = ["10.1.2.0/24"]
      }

      pe-subnet = {
        address_prefix = ["10.1.3.0/24"]
      }

      AzureBastionSubnet = {
        address_prefix = ["10.1.4.0/26"]
      }
    }
  }
}

vault_password = "r3P1iKa5x_123"