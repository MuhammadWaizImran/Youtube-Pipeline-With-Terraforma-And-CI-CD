# Glue Data Catalog databases (bronze/silver/gold) + the two Glue jobs +
# an Athena workgroup. The job scripts themselves are uploaded once here
# (lifecycle.ignore_changes on content) — day-to-day script edits go
# through aws-glue-deploy.yml's `aws s3 cp`, which never touches this
# module's Terraform state (same pattern as the Azure Databricks
# job-deploy workflow).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_glue_catalog_database" "layers" {
  for_each = toset(["bronze", "silver", "gold"])
  name     = "${replace(var.project, "-", "_")}_${each.value}_${var.env}"
}

resource "aws_s3_object" "bronze_to_silver_script" {
  bucket = var.scripts_bucket_name
  key    = "glue_jobs/bronze_to_silver_statistics.py"
  source = var.bronze_to_silver_script_path
  etag   = filemd5(var.bronze_to_silver_script_path)

  lifecycle {
    ignore_changes = [source, etag]
  }
}

resource "aws_s3_object" "silver_to_gold_script" {
  bucket = var.scripts_bucket_name
  key    = "glue_jobs/silver_to_gold_analytics.py"
  source = var.silver_to_gold_script_path
  etag   = filemd5(var.silver_to_gold_script_path)

  lifecycle {
    ignore_changes = [source, etag]
  }
}

resource "aws_glue_job" "bronze_to_silver" {
  name              = "${var.project}-bronze-to-silver-${var.env}"
  role_arn          = var.glue_role_arn
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  max_retries       = 0
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.bronze_to_silver_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"
  }

  tags = var.tags
}

resource "aws_glue_job" "silver_to_gold" {
  name              = "${var.project}-silver-to-gold-${var.env}"
  role_arn          = var.glue_role_arn
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  max_retries       = 0
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.silver_to_gold_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language" = "python"
  }

  tags = var.tags
}

resource "aws_athena_workgroup" "this" {
  name = "${var.project}-${var.env}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.scripts_bucket_name}/athena-results/"
    }
  }

  tags = var.tags
}
