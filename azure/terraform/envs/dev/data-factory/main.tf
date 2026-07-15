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

data "terraform_remote_state" "databricks" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/databricks.tfstate" })
}

data "terraform_remote_state" "functions" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/functions.tfstate" })
}

data "terraform_remote_state" "monitoring" {
  backend = "azurerm"
  config  = merge(local.remote_state_common, { key = "dev/monitoring.tfstate" })
}

module "data_factory" {
  source = "../../../modules/data-factory"

  project             = "ytpipeline"
  env                 = "dev"
  resource_group_name = data.terraform_remote_state.storage.outputs.resource_group_name
  location            = data.terraform_remote_state.storage.outputs.location
  identity_id         = data.terraform_remote_state.security.outputs.data_factory_identity_id

  databricks_workspace_url         = data.terraform_remote_state.databricks.outputs.workspace_url
  databricks_workspace_id          = data.terraform_remote_state.databricks.outputs.workspace_id
  databricks_job_cluster_policy_id = data.terraform_remote_state.databricks.outputs.job_cluster_policy_id

  function_app_names = data.terraform_remote_state.functions.outputs.function_app_names
  function_app_ids   = data.terraform_remote_state.functions.outputs.function_app_ids
  function_keys      = var.function_keys

  action_group_id = data.terraform_remote_state.monitoring.outputs.action_group_id

  pipeline_definition_path = "${path.module}/../../../data_factory/pipeline_definition.json"

  tags = {
    project     = "ytpipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
