# Key Vault (replaces the raw YOUTUBE_API_KEY env var) + one user-assigned
# managed identity per compute layer (Functions, ADF, Databricks), each
# granted least-privilege RBAC on the shared storage account. Mirrors the
# AWS iam_permission/*.json role-per-service pattern.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = substr("kv-${var.project}-${var.env}", 0, 24)
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true
  tags                       = var.tags
}

resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "youtube_api_key" {
  name         = "youtube-api-key"
  value        = var.youtube_api_key
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.deployer_kv_officer]
}

# ── Managed identities ────────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "functions" {
  name                = "id-${var.project}-functions-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "data_factory" {
  name                = "id-${var.project}-adf-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "databricks" {
  name                = "id-${var.project}-databricks-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── RBAC: data-plane access to ADLS Gen2 ──────────────────────────────────

resource "azurerm_role_assignment" "functions_storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}

resource "azurerm_role_assignment" "data_factory_storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.data_factory.principal_id
}

resource "azurerm_role_assignment" "databricks_storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.databricks.principal_id
}

# ── RBAC: read access to the API key secret ───────────────────────────────

resource "azurerm_role_assignment" "functions_kv_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.functions.principal_id
}
