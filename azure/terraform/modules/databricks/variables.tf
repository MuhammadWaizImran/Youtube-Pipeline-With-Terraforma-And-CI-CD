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

variable "metastore_id" {
  description = <<-EOT
    ID of the Unity Catalog metastore for this region. Metastore
    creation/assignment is an account-level, one-time-per-region operation
    performed outside this module (Databricks account console or a
    separate `account`-provider bootstrap config) — pass its ID in here.
  EOT
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
