terraform {
  backend "azurerm" {
    key = "dev/data-factory.tfstate"
  }
}
