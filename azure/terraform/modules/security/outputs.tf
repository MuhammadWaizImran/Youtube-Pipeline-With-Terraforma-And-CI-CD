output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "youtube_api_key_secret_name" {
  value = azurerm_key_vault_secret.youtube_api_key.name
}

output "functions_identity_id" {
  value = azurerm_user_assigned_identity.functions.id
}

output "functions_identity_client_id" {
  value = azurerm_user_assigned_identity.functions.client_id
}

output "functions_identity_principal_id" {
  value = azurerm_user_assigned_identity.functions.principal_id
}

output "data_factory_identity_id" {
  value = azurerm_user_assigned_identity.data_factory.id
}

output "data_factory_identity_principal_id" {
  value = azurerm_user_assigned_identity.data_factory.principal_id
}

output "databricks_identity_id" {
  value = azurerm_user_assigned_identity.databricks.id
}

output "databricks_identity_principal_id" {
  value = azurerm_user_assigned_identity.databricks.principal_id
}
