output "workspace_id" {
  value = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  value = azurerm_databricks_workspace.this.workspace_url
}

output "catalog_names" {
  value = { for k, v in databricks_catalog.layers : k => v.name }
}

output "job_cluster_policy_id" {
  value = databricks_cluster_policy.job_default.id
}

output "sql_warehouse_id" {
  value = databricks_sql_endpoint.analytics.id
}

output "sql_warehouse_jdbc_url" {
  value = databricks_sql_endpoint.analytics.jdbc_url
}
