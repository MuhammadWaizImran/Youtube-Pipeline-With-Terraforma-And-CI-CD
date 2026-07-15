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

# Reads the `storage` module's outputs from its own, independent state file
# — this is how cross-module wiring works without merging state.
data "terraform_remote_state" "storage" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "dev/storage.tfstate"
  }
}

module "security" {
  source = "../../../modules/security"

  project             = "ytpipeline"
  env                 = "dev"
  resource_group_name = data.terraform_remote_state.storage.outputs.resource_group_name
  location            = data.terraform_remote_state.storage.outputs.location
  storage_account_id  = data.terraform_remote_state.storage.outputs.storage_account_id
  youtube_api_key     = var.youtube_api_key

  tags = {
    project     = "ytpipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
