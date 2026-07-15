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

data "terraform_remote_state" "monitoring" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/monitoring.tfstate" })
}

data "terraform_remote_state" "glue" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/glue.tfstate" })
}

data "terraform_remote_state" "lambda" {
  backend = "s3"
  config  = merge(local.remote_state_common, { key = "dev/lambda.tfstate" })
}

module "orchestration" {
  source = "../../../modules/orchestration"

  project              = "yt-data-pipeline"
  env                  = "dev"
  sfn_role_arn         = data.terraform_remote_state.security.outputs.sfn_role_arn
  eventbridge_role_arn = data.terraform_remote_state.security.outputs.eventbridge_role_arn

  template_path = "${path.module}/../../../../step_functions/pipeline_orchestration.tftpl"

  ingestion_function_arn       = data.terraform_remote_state.lambda.outputs.ingestion_function_arn
  json_to_parquet_function_arn = data.terraform_remote_state.lambda.outputs.json_to_parquet_function_arn
  data_quality_function_arn    = data.terraform_remote_state.lambda.outputs.data_quality_function_arn

  bronze_to_silver_job_name = data.terraform_remote_state.glue.outputs.bronze_to_silver_job_name
  silver_to_gold_job_name   = data.terraform_remote_state.glue.outputs.silver_to_gold_job_name

  bronze_database = data.terraform_remote_state.glue.outputs.database_names["bronze"]
  silver_database = data.terraform_remote_state.glue.outputs.database_names["silver"]
  gold_database   = data.terraform_remote_state.glue.outputs.database_names["gold"]

  silver_bucket_name = data.terraform_remote_state.storage.outputs.bucket_names["silver"]
  gold_bucket_name   = data.terraform_remote_state.storage.outputs.bucket_names["gold"]

  sns_topic_arn = data.terraform_remote_state.monitoring.outputs.sns_topic_arn

  schedule_expression = var.schedule_expression
  schedule_enabled    = var.schedule_enabled

  tags = {
    project     = "yt-data-pipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
