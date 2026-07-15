output "workspace_id" {
  value = module.databricks.workspace_id
}

output "workspace_url" {
  value = module.databricks.workspace_url
}

output "catalog_names" {
  value = module.databricks.catalog_names
}

output "job_cluster_policy_id" {
  value = module.databricks.job_cluster_policy_id
}

output "sql_warehouse_id" {
  value = module.databricks.sql_warehouse_id
}
