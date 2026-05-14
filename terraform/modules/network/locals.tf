
locals {
  client_ip = chomp(data.http.client_ip.response_body)
}


locals {
  network_structure = {
    dev-vnet = {
      address_space = ["10.1.0.0/16"]

      subnets = {
        app-subnet = {
          address_prefix = ["10.1.1.0/24"]
        }

        pe-subnet = {
          address_prefix = ["10.1.3.0/24"]
        }
      }
    }
  }
}

locals {
  nsg_rules = {
    ssh = {
      name        = "Allow-SSH"
      port        = 22
      priority    = 100
      direction   = "Inbound"
      source      = "client_ip"
      destination = "app_subnet"
      target_nsgs = ["dev-vnet-app-subnet"]
    }

    winrm_http = {
      name        = "Allow-WinRM-HTTP"
      port        = 5985
      priority    = 110
      direction   = "Inbound"
      source      = "client_ip"
      destination = "app_subnet"
      target_nsgs = ["dev-vnet-app-subnet"]
    }

    rdp = {
      name        = "Allow-RDP"
      port        = 3389
      priority    = 120
      direction   = "Inbound"
      source      = "client_ip"
      destination = "app_subnet"
      target_nsgs = ["dev-vnet-app-subnet"]
    }

    sql = {
      name        = "Allow-SQL"
      port        = 1433
      direction   = "Outbound"
      source      = "app_subnet"
      destination = "pe_subnet"
      priority    = 140
      target_nsgs = ["dev-vnet-app-subnet"]

    }
  }
}

locals {
  cidr_map = {
    app_subnet = local.network_structure["dev-vnet"].subnets["app-subnet"].address_prefix[0]
    pe_subnet  = local.network_structure["dev-vnet"].subnets["pe-subnet"].address_prefix[0]
    client_ip  = local.client_ip
  }
}

locals {
  nsg_rule_matrix = merge([
    for nsg_key, nsg in azurerm_network_security_group.nsg : {
      for rule_key, rule in local.nsg_rules :
      "${nsg_key}-${rule_key}" => {
        nsg_key = nsg_key
        nsg     = nsg
        rule    = rule
      }
    if contains(rule.target_nsgs, nsg_key) }
  ]...)
}

locals {

  subnets = flatten([
    for vnet_name, vnet in var.network_structure : [
      for subnet_name, subnet_obj in vnet.subnets : {
        vnet_name   = vnet_name
        subnet_name = subnet_name
        prefix      = subnet_obj.address_prefix
      }
    ]
  ])

  subnet_map = {
    for subnet in local.subnets :
    "${subnet.vnet_name}-${subnet.subnet_name}" => subnet
  }
}



