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

locals {
  remote_state_common = {
    bucket = var.tfstate_bucket
    region = var.tfstate_region
  }
}

data "terraform_remote_state" "storage" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/storage.tfstate" })
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/security.tfstate" })
}

module "glue" {
  source = "../../../modules/glue"

  project             = "yt-data-pipeline"
  env                 = "dev"
  glue_role_arn       = data.terraform_remote_state.security.outputs.glue_role_arn
  scripts_bucket_name = data.terraform_remote_state.storage.outputs.bucket_names["scripts"]
  silver_bucket_name  = data.terraform_remote_state.storage.outputs.bucket_names["silver"]
  gold_bucket_name    = data.terraform_remote_state.storage.outputs.bucket_names["gold"]

  bronze_to_silver_script_path = "${path.module}/../../../../../glue_jobs/bronze_to_silver_statistics.py"
  silver_to_gold_script_path   = "${path.module}/../../../../../glue_jobs/silver_to_gold_analytics.py"

  tags = {
    project     = "yt-data-pipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
