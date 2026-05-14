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