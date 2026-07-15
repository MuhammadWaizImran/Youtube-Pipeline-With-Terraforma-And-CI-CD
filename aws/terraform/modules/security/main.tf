# IAM roles — one per service, mirrors the role-per-service pattern in
# ../../../iam_permission/*.json (those files were the manual reference
# docs; this module is the same permissions, Terraform-managed). Scoped
# with wildcards on the shared "${project}-*" naming convention rather
# than exact ARNs, so a new Lambda/Glue job added later doesn't require
# editing IAM policy — avoids the circular-module-dependency problem
# (roles are needed before the resources that would give us exact ARNs).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ── Lambda: ingestion ───────────────────────────────────────────────────
resource "aws_iam_role" "lambda_ingestion" {
  name               = "${var.project}-lambda-ingestion-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_ingestion_basic" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ingestion" {
  name = "s3-sns"
  role = aws_iam_role.lambda_ingestion.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Access"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [var.bronze_bucket_arn, "${var.bronze_bucket_arn}/*"]
      },
      {
        Sid      = "SNSAccess"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.project}-*"
      }
    ]
  })
}

# ── Lambda: json_to_parquet ─────────────────────────────────────────────
resource "aws_iam_role" "lambda_json_to_parquet" {
  name               = "${var.project}-lambda-json-to-parquet-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_json_to_parquet_basic" {
  role       = aws_iam_role.lambda_json_to_parquet.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_json_to_parquet" {
  name = "s3-glue-sns"
  role = aws_iam_role.lambda_json_to_parquet.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          var.bronze_bucket_arn, "${var.bronze_bucket_arn}/*",
          var.silver_bucket_arn, "${var.silver_bucket_arn}/*",
        ]
      },
      {
        Sid    = "GlueAccess"
        Effect = "Allow"
        Action = [
          "glue:GetTable", "glue:GetDatabase", "glue:CreateTable",
          "glue:UpdateTable", "glue:GetPartitions", "glue:CreatePartition",
          "glue:BatchCreatePartition",
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSAccess"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.project}-*"
      }
    ]
  })
}

# ── Lambda: data_quality ────────────────────────────────────────────────
resource "aws_iam_role" "lambda_dq" {
  name               = "${var.project}-lambda-dq-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_dq_basic" {
  role       = aws_iam_role.lambda_dq.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dq" {
  name = "athena-s3-glue-sns"
  role = aws_iam_role.lambda_dq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AthenaAccess"
        Effect   = "Allow"
        Action   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults"]
        Resource = "*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          var.silver_bucket_arn, "${var.silver_bucket_arn}/*",
          var.scripts_bucket_arn, "${var.scripts_bucket_arn}/*",
        ]
      },
      {
        Sid      = "GlueAccess"
        Effect   = "Allow"
        Action   = ["glue:GetTable", "glue:GetDatabase"]
        Resource = "*"
      },
      {
        Sid      = "SNSAccess"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.project}-*"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── Glue ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "glue" {
  name = "${var.project}-glue-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue" {
  name = "s3-full-access"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3FullAccess"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
      Resource = [
        var.bronze_bucket_arn, "${var.bronze_bucket_arn}/*",
        var.silver_bucket_arn, "${var.silver_bucket_arn}/*",
        var.gold_bucket_arn, "${var.gold_bucket_arn}/*",
        var.scripts_bucket_arn, "${var.scripts_bucket_arn}/*",
      ]
    }]
  })
}

# ── Step Functions ───────────────────────────────────────────────────────
resource "aws_iam_role" "sfn" {
  name = "${var.project}-sfn-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "sfn" {
  name = "lambda-glue-sns"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${local.region}:${local.account_id}:function:${var.project}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.project}-*"
      }
    ]
  })
}

# ── EventBridge (triggers the state machine on schedule) ────────────────
resource "aws_iam_role" "eventbridge" {
  name = "${var.project}-eventbridge-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "start-execution"
  role = aws_iam_role.eventbridge.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${var.project}-*"
    }]
  })
}
