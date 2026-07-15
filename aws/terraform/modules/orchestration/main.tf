# Step Functions state machine (replaces manual `aws stepfunctions
# create-state-machine`) + EventBridge schedule rule (replaces manual
# `aws events put-rule`/`put-targets`). This is the module the user asked
# to isolate: changing ONLY the schedule_expression variable, or editing
# the pipeline_orchestration.tftpl control flow, only ever touches this
# module's state file — storage/lambda/glue/security are untouched.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project}-${var.env}"
  role_arn = var.sfn_role_arn

  definition = templatefile(var.template_path, {
    ingestion_function_arn       = var.ingestion_function_arn
    json_to_parquet_function_arn = var.json_to_parquet_function_arn
    data_quality_function_arn    = var.data_quality_function_arn
    bronze_to_silver_job_name    = var.bronze_to_silver_job_name
    silver_to_gold_job_name      = var.silver_to_gold_job_name
    bronze_database              = var.bronze_database
    silver_database              = var.silver_database
    gold_database                = var.gold_database
    silver_bucket_name           = var.silver_bucket_name
    gold_bucket_name             = var.gold_bucket_name
    sns_topic_arn                = var.sns_topic_arn
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project}-schedule-${var.env}"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "sfn" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = var.eventbridge_role_arn
}
