terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
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

data "terraform_remote_state" "monitoring" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/monitoring.tfstate" })
}

data "terraform_remote_state" "glue" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/glue.tfstate" })
}

module "lambda" {
  source = "../../../modules/lambda"

  project = "yt-data-pipeline"
  env     = "dev"
  region  = "us-east-1"

  lambda_ingestion_role_arn       = data.terraform_remote_state.security.outputs.lambda_ingestion_role_arn
  lambda_json_to_parquet_role_arn = data.terraform_remote_state.security.outputs.lambda_json_to_parquet_role_arn
  lambda_dq_role_arn              = data.terraform_remote_state.security.outputs.lambda_dq_role_arn

  ingestion_source_dir       = "${path.module}/../../../../../lambdas/youtube_api_integstion"
  json_to_parquet_source_dir = "${path.module}/../../../../../lambdas/json_to_parquet"
  dq_source_dir              = "${path.module}/../../../../../data_quality"

  bronze_bucket_name = data.terraform_remote_state.storage.outputs.bucket_names["bronze"]
  silver_bucket_name = data.terraform_remote_state.storage.outputs.bucket_names["silver"]
  silver_database    = data.terraform_remote_state.glue.outputs.database_names["silver"]
  athena_workgroup   = data.terraform_remote_state.glue.outputs.athena_workgroup_name

  youtube_api_key = var.youtube_api_key
  sns_topic_arn   = data.terraform_remote_state.monitoring.outputs.sns_topic_arn

  tags = {
    project     = "yt-data-pipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
