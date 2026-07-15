output "function_app_names" {
  value = { for k, v in azurerm_linux_function_app.this : k => v.name }
}

output "function_app_default_hostnames" {
  value = { for k, v in azurerm_linux_function_app.this : k => v.default_hostname }
}

output "function_app_ids" {
  value = { for k, v in azurerm_linux_function_app.this : k => v.id }
}
