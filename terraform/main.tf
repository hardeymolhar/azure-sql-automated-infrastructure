module "network" {
  source = "./modules/network"

  primary_rg   = local.primary_rg
  secondary_rg = local.secondary_rg

  primary_location   = local.primary_location
  secondary_location = local.secondary_location

  network_structure = var.network_structure

  client_ip = local.client_ip
}


module "vm" {
  source = "./modules/vm"

  primary_rg   = local.primary_rg
  secondary_rg = local.secondary_rg

  primary_location   = local.primary_location
  secondary_location = local.secondary_location

  admin_username = var.admin_username
  admin_password = var.admin_password

  vm_count       = var.vm_count
  linux_vm_count = var.linux_vm_count

  vm_name = var.vm_name
  vm_size = var.vm_size

  availability_zone = var.availability_zone

  image_publisher = var.image_publisher
  image_offer     = var.image_offer
  image_sku       = var.image_sku
  image_version   = var.image_version

  data_disks_per_vm = var.data_disks_per_vm
  log_disks_per_vm  = var.log_disks_per_vm

  data_disks_per_linux_vm = var.data_disks_per_linux_vm
  log_disks_per_linux_vm  = var.log_disks_per_linux_vm

  storage_connection_string = data.terraform_remote_state.storage.outputs.primary_connection_string

  client_ip = local.client_ip
}



module "monitoring" {
  source = "./modules/monitoring"

  primary_rg       = local.primary_rg
  primary_location = local.primary_location
}


module "sql" {
  source = "./modules/sql"

  primary_rg   = local.primary_rg
  secondary_rg = local.secondary_rg

  primary_location   = local.primary_location
  secondary_location = local.secondary_location

  client_ip = local.client_ip

  sqladmin_username = var.sqladmin_username
  sqladmin_password = var.sqladmin_password
}

module "private_endpoints" {
  source = "./modules/private-endpoints"

  primary_rg       = local.primary_rg
  primary_location = local.primary_location

  secondary_rg       = local.secondary_rg
  secondary_location = local.secondary_location
}