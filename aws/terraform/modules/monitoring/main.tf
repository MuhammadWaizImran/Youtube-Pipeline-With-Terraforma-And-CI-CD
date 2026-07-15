# SNS topic (+ email subscription) exactly like the manual
# `aws sns create-topic` / `aws sns subscribe` steps in the root README,
# plus a CloudWatch Log Group for the pipeline's Lambdas.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts-${var.env}"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/${var.project}/${var.env}"
  retention_in_days = 30
  tags              = var.tags
}
