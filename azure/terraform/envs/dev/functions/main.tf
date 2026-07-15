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

locals {
  remote_state_common = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
  }
}

data "terraform_remote_state" "storage" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/storage.tfstate" })
}

data "terraform_remote_state" "security" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/security.tfstate" })
}

data "terraform_remote_state" "monitoring" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/monitoring.tfstate" })
}

data "terraform_remote_state" "databricks" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/databricks.tfstate" })
}

module "functions" {
  source = "../../../modules/functions"

  project                              = "ytpipeline"
  env                                  = "dev"
  resource_group_name                  = data.terraform_remote_state.storage.outputs.resource_group_name
  location                             = data.terraform_remote_state.storage.outputs.location
  storage_account_name                 = data.terraform_remote_state.storage.outputs.storage_account_name
  storage_account_primary_dfs_endpoint = data.terraform_remote_state.storage.outputs.storage_account_primary_dfs_endpoint
  identity_id                          = data.terraform_remote_state.security.outputs.functions_identity_id
  identity_client_id                   = data.terraform_remote_state.security.outputs.functions_identity_client_id
  key_vault_uri                        = data.terraform_remote_state.security.outputs.key_vault_uri
  youtube_api_key_secret_name          = data.terraform_remote_state.security.outputs.youtube_api_key_secret_name
  action_group_id                      = data.terraform_remote_state.monitoring.outputs.action_group_id
  databricks_host                      = data.terraform_remote_state.databricks.outputs.workspace_url
  databricks_warehouse_id              = data.terraform_remote_state.databricks.outputs.sql_warehouse_id

  tags = {
    project     = "ytpipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
