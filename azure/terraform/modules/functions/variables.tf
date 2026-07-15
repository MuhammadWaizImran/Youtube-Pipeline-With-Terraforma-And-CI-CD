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

variable "storage_account_name" {
  type = string
}

variable "storage_account_primary_dfs_endpoint" {
  type = string
}

variable "identity_id" {
  type = string
}

variable "identity_client_id" {
  type = string
}

variable "key_vault_uri" {
  type = string
}

variable "youtube_api_key_secret_name" {
  type = string
}

variable "youtube_regions" {
  type    = string
  default = "US,GB,CA,DE,FR,IN,JP,KR,MX,RU"
}

variable "action_group_id" {
  description = "Azure Monitor Action Group ID used as the alert target (replaces SNS_ALERT_TOPIC_ARN)"
  type        = string
}

variable "databricks_host" {
  description = "https://<workspace-url> — used by the data-quality function to query the SQL Warehouse (Athena replacement)"
  type        = string
}

variable "databricks_warehouse_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
