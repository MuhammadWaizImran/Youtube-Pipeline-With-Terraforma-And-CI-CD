terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "terraform_remote_state" "storage" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "dev/storage.tfstate"
    region = var.tfstate_region
  }
}

module "security" {
  source = "../../../modules/security"

  project            = "yt-data-pipeline"
  env                = "dev"
  bronze_bucket_arn  = data.terraform_remote_state.storage.outputs.bucket_arns["bronze"]
  silver_bucket_arn  = data.terraform_remote_state.storage.outputs.bucket_arns["silver"]
  gold_bucket_arn    = data.terraform_remote_state.storage.outputs.bucket_arns["gold"]
  scripts_bucket_arn = data.terraform_remote_state.storage.outputs.bucket_arns["scripts"]

  tags = {
    project     = "yt-data-pipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
