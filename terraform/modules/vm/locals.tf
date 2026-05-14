locals {
  # derived counts
  win_data_disk_count = var.vm_count * var.data_disks_per_vm
  win_log_disk_count  = var.vm_count * var.log_disks_per_vm


  lin_data_disk_count = var.linux_vm_count * var.data_disks_per_linux_vm
  lin_log_disk_count  = var.linux_vm_count * var.log_disks_per_linux_vm

  # LUN layout
  data_lun_start = 2
  log_lun_start  = local.data_lun_start + var.data_disks_per_vm

}
