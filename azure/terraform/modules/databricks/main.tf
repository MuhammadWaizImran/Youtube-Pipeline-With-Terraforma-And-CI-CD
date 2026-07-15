# Databricks workspace (replaces Glue compute) + Unity Catalog wiring
# (replaces the Glue Data Catalog) + a serverless SQL Warehouse
# (replaces Athena) + a shared job cluster policy for the two PySpark jobs.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.49"
    }
  }
}

resource "azurerm_databricks_workspace" "this" {
  name                = "dbw-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "premium" # required for Unity Catalog + RBAC-based cluster policies
  tags                = var.tags
}

# Access connector = the managed identity Unity Catalog uses to read/write
# the ADLS Gen2 storage account (Azure's equivalent of a Glue/EMR IAM role).
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "access_connector_storage" {
  scope                = data.azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

data "azurerm_storage_account" "adls" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

provider "databricks" {
  host = azurerm_databricks_workspace.this.workspace_url
}

resource "databricks_storage_credential" "adls" {
  name = "cred-${var.project}-${var.env}"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.this.id
  }
  depends_on = [azurerm_role_assignment.access_connector_storage]
}

resource "databricks_external_location" "layers" {
  for_each        = toset(["bronze", "silver", "gold", "scripts"])
  name            = "${each.value}-${var.env}"
  url             = "abfss://${each.value}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.adls.id
}

resource "databricks_catalog" "layers" {
  for_each     = toset(["bronze", "silver", "gold"])
  name         = "${var.project}_${each.value}_${var.env}"
  metastore_id = var.metastore_id
  storage_root = "abfss://${each.value}@${var.storage_account_name}.dfs.core.windows.net/"

  depends_on = [databricks_external_location.layers]
}

resource "databricks_schema" "youtube" {
  for_each     = databricks_catalog.layers
  catalog_name = each.value.name
  name         = "youtube"
}

# Shared cluster policy for the two migrated PySpark jobs — keeps job
# clusters small/ephemeral (job-scoped, autoterminating), analogous to
# Glue's G.1X worker sizing in the AWS version.
resource "databricks_cluster_policy" "job_default" {
  name = "${var.project}-${var.env}-job-default"
  definition = jsonencode({
    "spark_version" : { "type" : "fixed", "value" : "14.3.x-scala2.12" },
    "node_type_id" : { "type" : "fixed", "value" : "Standard_DS3_v2" },
    "autotermination_minutes" : { "type" : "fixed", "value" : 20 },
    "num_workers" : { "type" : "range", "minValue" : 1, "maxValue" : 4 }
  })
}

resource "databricks_sql_endpoint" "analytics" {
  name                      = "${var.project}-${var.env}-analytics"
  cluster_size              = "2X-Small"
  auto_stop_mins            = 15
  min_num_clusters          = 1
  max_num_clusters          = 2
  enable_serverless_compute = true
}
