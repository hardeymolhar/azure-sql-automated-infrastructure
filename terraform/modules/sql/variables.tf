variable "sqladmin_username" {
  description = "SQL Admin username"
  type        = string
  default     = "sqladmin"
}


variable "sqladmin_password" {
  description = "SQL Admin password"
  type        = string
  sensitive   = true
}

variable "primary_rg" {
  type = string
}

variable "secondary_rg" {
  type = string
}

variable "primary_location" {
  type = string
}

variable "secondary_location" {
  type = string
}

variable "client_ip" {
  type = string
}