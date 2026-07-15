terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.49"
    }
  }
}

provider "azurerm" {
  features {}
}

data "terraform_remote_state" "storage" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "dev/storage.tfstate"
  }
}

module "databricks" {
  source = "../../../modules/databricks"

  project              = "ytpipeline"
  env                  = "dev"
  resource_group_name  = data.terraform_remote_state.storage.outputs.resource_group_name
  location             = data.terraform_remote_state.storage.outputs.location
  storage_account_name = data.terraform_remote_state.storage.outputs.storage_account_name
  metastore_id         = var.metastore_id

  tags = {
    project     = "ytpipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
