/* 
This block tells Terraform what tools (providers) it needs to download 
before it can do anything.

Think of it like installing apps before using them.
*/
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0.0" # Use a stable Azure provider version
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0" # Used for generating security keys
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4" # Used for creating files on your machine
    }
  }

  required_version = ">= 1.4.0" # Ensures Terraform itself is a compatible version
}

# 1.4.0 1 means Major Update, 4 means Minor Update, 0 means Patch Update.

/* 
This block tells Terraform how to connect to Azure.

Think of it like logging into your Azure account so Terraform can create resources there.
*/
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
}