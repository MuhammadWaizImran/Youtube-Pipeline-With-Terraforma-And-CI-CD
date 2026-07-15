terraform {
  backend "azurerm" {
    key = "dev/databricks.tfstate"
  }
}
