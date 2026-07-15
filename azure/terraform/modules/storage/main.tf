# ADLS Gen2 storage for the medallion layers (replaces the AWS S3 buckets).
# One storage account, hierarchical namespace enabled, one filesystem
# container per layer — mirrors bronze/silver/gold/scripts from the AWS repo.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project}-${var.env}"
  location = var.location
  tags     = var.tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "adls" {
  name                     = substr("st${var.project}${var.env}${random_string.suffix.result}", 0, 24)
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # hierarchical namespace = ADLS Gen2
  min_tls_version          = "TLS1_2"
  tags                     = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "layers" {
  for_each           = toset(["bronze", "silver", "gold", "scripts"])
  name               = each.value
  storage_account_id = azurerm_storage_account.adls.id
}
