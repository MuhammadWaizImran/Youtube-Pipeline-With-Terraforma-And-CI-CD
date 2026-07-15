variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "identity_id" {
  type = string
}

variable "databricks_workspace_url" {
  type = string
}

variable "databricks_workspace_id" {
  description = "Full ARM resource ID of the Databricks workspace — used for MSI-based ADF authentication"
  type        = string
}

variable "databricks_job_cluster_policy_id" {
  type = string
}

variable "function_app_names" {
  description = "map: youtube-api-ingestion / json-to-parquet / data-quality -> Function App name"
  type        = map(string)
}

variable "function_app_ids" {
  type = map(string)
}

variable "action_group_id" {
  type = string
}

variable "function_keys" {
  description = <<-EOT
    Host keys for each Function App, keyed the same as function_app_names
    (youtube-api-ingestion / json-to-parquet / data-quality). ADF's
    AzureFunctionActivity authenticates with a function key, not the
    managed identity — these are only obtainable *after* the Function Apps
    in the `functions` module have been deployed at least once, so on a
    from-scratch environment this starts as a placeholder and is updated
    (via `terraform apply -var=...` or a follow-up PR) once real keys exist.
  EOT
  type        = map(string)
  sensitive   = true
}

variable "pipeline_definition_path" {
  description = "Path to the ADF pipeline activities JSON (mirrors step_functions/pipeline_orchestation.json)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
