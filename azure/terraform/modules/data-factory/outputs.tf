output "data_factory_id" {
  value = azurerm_data_factory.this.id
}

output "data_factory_name" {
  value = azurerm_data_factory.this.name
}

output "pipeline_name" {
  value = azurerm_data_factory_pipeline.orchestration.name
}
