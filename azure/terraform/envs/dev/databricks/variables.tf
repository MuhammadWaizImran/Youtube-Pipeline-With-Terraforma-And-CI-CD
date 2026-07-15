variable "tfstate_resource_group_name" {
  type = string
}

variable "tfstate_storage_account_name" {
  type = string
}

variable "tfstate_container_name" {
  type    = string
  default = "tfstate"
}

variable "metastore_id" {
  description = "Unity Catalog metastore ID for this region (created once at account level, see modules/databricks/variables.tf)"
  type        = string
}
