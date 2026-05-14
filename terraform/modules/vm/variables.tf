variable "admin_username" {
  description = "VM Admin username"
  type        = string
  default     = "azureuser"
}

variable "data_disks_per_linux_vm" {
  type    = number
  default = 2
}

variable "log_disks_per_linux_vm" {
  type    = number
  default = 2
}

variable "admin_password" {
  description = "VM Admin password"
  type        = string
}

variable "linux_vm_count" {
  type    = number
  default = 1
}

variable "vm_name" {
  type    = string
  default = "azure-vm-01"
}

variable "vm_size" {
  type    = string
  default = "Standard_D8s_v3"
}

variable "availability_zone" {
  type        = string
  default     = "3"
  description = "Availability zone (use \"1\", \"2\" or \"3\")"
}

variable "image_publisher" {
  type    = string
  default = "RedHat"
}


variable "image_offer" {
  type    = string
  default = "RHEL"
}

variable "image_sku" {
  type    = string
  default = "9-lvm-gen2"
}


variable "image_version" {
  type    = string
  default = "latest"
}


variable "vm_count" {
  type    = number
  default = 1
}

variable "data_disks_per_vm" {
  type    = number
  default = 2
}

variable "log_disks_per_vm" {
  type    = number
  default = 2
}

variable "primary_rg" {
  type = string
}

variable "secondary_rg" {
  type     = string
  nullable = true
  default  = null
}

variable "primary_location" {
  type = string
}

variable "secondary_location" {
  type     = string
  nullable = true
  default  = null
}

variable "client_ip" {
  type = string
}

variable "storage_connection_string" {
  type      = string
  sensitive = true
}