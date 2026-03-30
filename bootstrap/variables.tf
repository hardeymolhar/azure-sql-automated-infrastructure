variable "rg" {
  type        = list(string)
  description = "Resource group name"
}

variable "location" {
  type        = list(string)
  description = "Azure region for all resources."
}


variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}