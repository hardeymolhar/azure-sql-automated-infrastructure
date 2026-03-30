locals {
  primary_location   = var.location[0]
  secondary_location = length(var.location) > 1 ? var.location[1] : null

  primary_rg   = var.rg[0]
  secondary_rg = length(var.rg) > 1 ? var.rg[1] : null
  tertiary_rg  = length(var.rg) > 2 ? var.rg[2] : null
}



locals {
  client_ip = chomp(data.http.client_ip.response_body)
}

locals {
  storage_accounts = {
    multimedia = {
      name = "multimedia12151"
    }

    tfstate = {
      name = "tfstate21151"
    }
  }
}
