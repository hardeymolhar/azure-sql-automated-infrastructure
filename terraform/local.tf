
locals {
  client_ip = chomp(data.http.client_ip.response_body)
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




locals {
  # derived counts
  data_disk_count = var.vm_count * var.data_disks_per_vm
  log_disk_count  = var.vm_count * var.log_disks_per_vm

  # LUN layout
  data_lun_start = 2
  log_lun_start  = local.data_lun_start + var.data_disks_per_vm

  # ordered resource groups
  primary_rg   = var.rg[0]
  secondary_rg = length(var.rg) > 1 ? var.rg[1] : null
  tertiary_rg  = length(var.rg) > 2 ? var.rg[2] : null

  # primary deployment location
  primary_location = var.location[0]
  secondary_location = length(var.location) > 1 ? var.location[1] : null
  tertiary_location  = length(var.location) > 2 ? var.location[2] : null
}
