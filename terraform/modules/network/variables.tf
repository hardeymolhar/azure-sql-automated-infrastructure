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


variable "network_structure" {
  type = map(object({
    address_space = list(string)

    subnets = map(object({
      address_prefix = list(string)
    }))
  }))
}


variable "client_ip" {
  type = string
}