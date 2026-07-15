terraform {
  backend "azurerm" {
    key = "dev/functions.tfstate"
  }
}
