# 3 Lambda functions, zipped straight from the existing
# lambdas/*/lambda_function.py + data_quality/dq_lambda.py source (no
# rewrite needed — that code is already AWS-native). Code-only edits are
# deployed by aws-lambda-deploy.yml's `aws lambda update-function-code`,
# which never touches this module's Terraform state — the `filename`/
# `source_code_hash` here just seed the function at creation time.

terraform {
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

data "archive_file" "ingestion" {
  type        = "zip"
  source_dir  = var.ingestion_source_dir
  output_path = "${path.module}/.build/ingestion.zip"
}

data "archive_file" "json_to_parquet" {
  type        = "zip"
  source_dir  = var.json_to_parquet_source_dir
  output_path = "${path.module}/.build/json_to_parquet.zip"
}

data "archive_file" "dq" {
  type        = "zip"
  source_dir  = var.dq_source_dir
  output_path = "${path.module}/.build/dq.zip"
}

resource "aws_lambda_function" "ingestion" {
  function_name = "${var.project}-youtube-ingestion-${var.env}"
  role          = var.lambda_ingestion_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.ingestion.output_path
  source_code_hash = data.archive_file.ingestion.output_base64sha256

  environment {
    variables = {
      YOUTUBE_API_KEY     = var.youtube_api_key
      S3_BUCKET_BRONZE    = var.bronze_bucket_name
      YOUTUBE_REGIONS     = var.youtube_regions
      SNS_ALERT_TOPIC_ARN = var.sns_topic_arn
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = var.tags
}

resource "aws_lambda_function" "json_to_parquet" {
  function_name = "${var.project}-json-to-parquet-${var.env}"
  role          = var.lambda_json_to_parquet_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 512
  layers        = [var.awswrangler_layer_arn]

  filename         = data.archive_file.json_to_parquet.output_path
  source_code_hash = data.archive_file.json_to_parquet.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_SILVER     = var.silver_bucket_name
      GLUE_DB_SILVER       = var.silver_database
      GLUE_TABLE_REFERENCE = var.reference_table_name
      SNS_ALERT_TOPIC_ARN  = var.sns_topic_arn
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = var.tags
}

resource "aws_lambda_function" "data_quality" {
  function_name = "${var.project}-data-quality-${var.env}"
  role          = var.lambda_dq_role_arn
  handler       = "dq_lambda.lambda_handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 512
  layers        = [var.awswrangler_layer_arn]

  filename         = data.archive_file.dq.output_path
  source_code_hash = data.archive_file.dq.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_SILVER    = var.silver_bucket_name
      SNS_ALERT_TOPIC_ARN = var.sns_topic_arn
      DQ_MIN_ROW_COUNT    = tostring(var.dq_min_row_count)
      DQ_MAX_NULL_PERCENT = tostring(var.dq_max_null_percent)
      ATHENA_WORKGROUP    = var.athena_workgroup
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = var.tags
}
