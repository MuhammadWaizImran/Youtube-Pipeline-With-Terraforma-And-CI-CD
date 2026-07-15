output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "storage_account_id" {
  value = azurerm_storage_account.adls.id
}

output "storage_account_name" {
  value = azurerm_storage_account.adls.name
}

output "storage_account_primary_dfs_endpoint" {
  value = azurerm_storage_account.adls.primary_dfs_endpoint
}

output "filesystem_names" {
  value = { for k, v in azurerm_storage_data_lake_gen2_filesystem.layers : k => v.name }
}
