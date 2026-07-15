# Azure Data Factory pipeline — replaces the AWS Step Functions state
# machine in step_functions/pipeline_orchestation.json. Linked services
# point at the Function Apps (ingestion / json-to-parquet / DQ gate) and
# the Databricks workspace (bronze->silver, silver->gold jobs). The
# pipeline's control flow (parallel branch, If Condition DQ gate, failure
# notifications) is defined in ../../../data_factory/pipeline_definition.json
# and deployed as-is via `activities_json`, so pipeline logic changes are a
# pure JSON edit — no Terraform resource replacement.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

resource "azurerm_data_factory" "this" {
  name                = "adf-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  tags = var.tags
}

resource "azurerm_data_factory_trigger_schedule" "every_6h" {
  name            = "trg-${var.project}-${var.env}-6h"
  data_factory_id = azurerm_data_factory.this.id
  pipeline_name   = azurerm_data_factory_pipeline.orchestration.name

  interval  = 6
  frequency = "Hour"
  activated = var.env == "prod"
}

resource "azurerm_data_factory_linked_service_azure_function" "youtube_api_ingestion" {
  name            = "ls-youtube-api-ingestion"
  data_factory_id = azurerm_data_factory.this.id
  url             = "https://${var.function_app_names["youtube-api-ingestion"]}.azurewebsites.net"
  key             = var.function_keys["youtube-api-ingestion"]
}

resource "azurerm_data_factory_linked_service_azure_function" "json_to_parquet" {
  name            = "ls-json-to-parquet"
  data_factory_id = azurerm_data_factory.this.id
  url             = "https://${var.function_app_names["json-to-parquet"]}.azurewebsites.net"
  key             = var.function_keys["json-to-parquet"]
}

resource "azurerm_data_factory_linked_service_azure_function" "data_quality" {
  name            = "ls-data-quality"
  data_factory_id = azurerm_data_factory.this.id
  url             = "https://${var.function_app_names["data-quality"]}.azurewebsites.net"
  key             = var.function_keys["data-quality"]
}

resource "azurerm_data_factory_linked_service_azure_databricks" "this" {
  name                       = "ls-databricks"
  data_factory_id            = azurerm_data_factory.this.id
  adb_domain                 = "https://${var.databricks_workspace_url}"
  msi_work_space_resource_id = var.databricks_workspace_id

  new_cluster_config {
    node_type             = "Standard_DS3_v2"
    cluster_version       = "14.3.x-scala2.12"
    min_number_of_workers = 1
    max_number_of_workers = 4
  }
}

resource "azurerm_data_factory_pipeline" "orchestration" {
  name            = "pl-${var.project}-${var.env}-orchestration"
  data_factory_id = azurerm_data_factory.this.id

  activities_json = file(var.pipeline_definition_path)

  variables = {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "pipeline_failed" {
  name                = "alert-${var.project}-${var.env}-pipeline-failed"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_data_factory.this.id]
  description         = "Fires when a pipeline run fails — mirrors the AWS Notify*Failure SNS states"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "pipeline_succeeded" {
  name                = "alert-${var.project}-${var.env}-pipeline-succeeded"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_data_factory.this.id]
  description         = "Fires on a successful pipeline run — mirrors the AWS NotifySuccess SNS state"
  severity            = 4
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineSucceededRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = var.action_group_id
  }
}
