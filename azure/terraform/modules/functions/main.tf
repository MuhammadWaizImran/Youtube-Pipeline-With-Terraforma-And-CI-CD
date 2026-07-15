# Three Linux Python Function Apps on a shared Consumption plan — one per
# AWS Lambda: youtube_api_ingestion, json_to_parquet, data_quality.
# Code deployment is intentionally NOT done here (see functions-deploy.yml);
# Terraform only owns the App shape, so a code-only change never touches
# this module's state.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

# Function Apps need their own storage account for deployment packages /
# triggers bookkeeping — separate from the ADLS Gen2 data lake account.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "funcapp" {
  name                     = substr("stfn${var.project}${var.env}${random_string.suffix.result}", 0, 24)
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  # B1 Basic — the Y1 Consumption/Dynamic plan hit a 0-quota "Total VMs"
  # restriction on this (new) Pay-As-You-Go subscription in eastus (Azure's
  # fraud-prevention default). B1 draws from the standard vCPU quota family
  # instead, which is available. Swap back to "Y1" once a Dynamic-workers
  # quota increase is approved for this subscription/region.
  sku_name = "B1"
  tags     = var.tags
}

locals {
  common_settings = {
    STORAGE_ACCOUNT_DFS_ENDPOINT = var.storage_account_primary_dfs_endpoint
    STORAGE_ACCOUNT_NAME         = var.storage_account_name
    AZURE_CLIENT_ID              = var.identity_client_id
    ACTION_GROUP_ID              = var.action_group_id
  }

  functions = {
    youtube-api-ingestion = {
      settings = {
        YOUTUBE_API_KEY  = "@Microsoft.KeyVault(VaultName=${element(split("/", replace(var.key_vault_uri, "https://", "")), 0)};SecretName=${var.youtube_api_key_secret_name})"
        BRONZE_CONTAINER = "bronze"
        YOUTUBE_REGIONS  = var.youtube_regions
      }
    }
    json-to-parquet = {
      settings = {
        SILVER_CONTAINER = "silver"
      }
    }
    data-quality = {
      settings = {
        SILVER_CONTAINER        = "silver"
        DQ_MIN_ROW_COUNT        = "10"
        DQ_MAX_NULL_PERCENT     = "5.0"
        DATABRICKS_HOST         = "https://${var.databricks_host}"
        DATABRICKS_WAREHOUSE_ID = var.databricks_warehouse_id
      }
    }
  }
}

resource "azurerm_linux_function_app" "this" {
  for_each = local.functions

  name                = "func-${var.project}-${each.key}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location

  storage_account_name       = azurerm_storage_account.funcapp.name
  storage_account_access_key = azurerm_storage_account.funcapp.primary_access_key
  service_plan_id            = azurerm_service_plan.this.id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = merge(local.common_settings, each.value.settings)

  tags = var.tags
}
