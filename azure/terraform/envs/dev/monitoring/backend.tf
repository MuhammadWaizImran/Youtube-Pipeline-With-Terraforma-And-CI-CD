terraform {
  backend "azurerm" {
    key = "dev/monitoring.tfstate"
  }
}
