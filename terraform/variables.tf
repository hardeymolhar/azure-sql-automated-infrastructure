variable "subscription_id" {
  description = "ID of the subscription"
  type        = string
}

variable "admin_username" {
  description = "VM Admin username"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "VM Admin username"
  type        = string
}
variable "rg" {
  type        = list(string)
  description = "Resource group name"
}

variable "vm_name" {
  type    = string
  default = "azure-vm-01"
}

variable "linux_vm_count" {
  type    = number
  default = 1
}

variable "vm_size" {
  type    = string
  default = "Standard_D8s_v3"
}

variable "data_disks_per_linux_vm" {
  type    = number
  default = 2
}

variable "log_disks_per_linux_vm" {
  type    = number
  default = 2
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

variable "location" {
  type        = list(string)
  description = "Azure region for resource deployment"
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

variable "network_structure" {
  type = map(object({
    address_space = list(string)

    subnets = map(object({
      address_prefix = list(string)
    }))
  }))
}


variable "vault_password" {
  sensitive = true
  type      = string
}

