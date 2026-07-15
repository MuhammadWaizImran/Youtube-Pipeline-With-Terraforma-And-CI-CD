terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

provider "azurerm" {
  features {}
}

module "storage" {
  source = "../../../modules/storage"

  project  = "ytpipeline"
  env      = "dev"
  location = "eastus"
  tags = {
    project     = "ytpipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
