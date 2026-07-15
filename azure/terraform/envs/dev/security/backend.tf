terraform {
  backend "azurerm" {
    key = "dev/security.tfstate"
  }
}
