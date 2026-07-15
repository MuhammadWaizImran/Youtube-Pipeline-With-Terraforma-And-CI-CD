# Partial backend config — bucket/dynamodb_table/region injected by CI via
# -backend-config= flags (see .github/workflows/aws-terraform-apply.yml),
# so this file works for every module/env without hardcoding the bootstrap
# bucket name.
terraform {
  backend "s3" {
    key = "dev/storage.tfstate"
  }
}
