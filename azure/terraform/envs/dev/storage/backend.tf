# Partial backend config — resource_group_name/storage_account_name/
# container_name are injected by CI via `-backend-config=` flags
# (see .github/workflows/terraform-apply.yml) so the same file works for
# every module/env without hardcoding the bootstrap storage account name.
terraform {
  backend "azurerm" {
    key = "dev/storage.tfstate"
  }
}
