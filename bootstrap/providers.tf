terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0.0" # adjust to your team's approved provider version
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  required_version = ">= 1.4.0"
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
}