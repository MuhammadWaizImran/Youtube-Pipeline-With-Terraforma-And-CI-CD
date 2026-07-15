output "key_vault_id" {
  value = module.security.key_vault_id
}

output "key_vault_name" {
  value = module.security.key_vault_name
}

output "key_vault_uri" {
  value = module.security.key_vault_uri
}

output "youtube_api_key_secret_name" {
  value = module.security.youtube_api_key_secret_name
}

output "functions_identity_id" {
  value = module.security.functions_identity_id
}

output "functions_identity_client_id" {
  value = module.security.functions_identity_client_id
}

output "data_factory_identity_id" {
  value = module.security.data_factory_identity_id
}

output "databricks_identity_id" {
  value = module.security.databricks_identity_id
}

output "databricks_identity_principal_id" {
  value = module.security.databricks_identity_principal_id
}
