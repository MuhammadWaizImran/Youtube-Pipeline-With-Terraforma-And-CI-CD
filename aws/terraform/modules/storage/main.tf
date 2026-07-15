# Bronze/Silver/Gold/Scripts S3 buckets — same 4-bucket layout the README's
# manual "aws s3 mb" steps describe, now Terraform-managed. Bucket names
# are globally unique across all of AWS, so a random suffix is appended
# (mirrors the ${region}-${env} suffix scripts/information.md used).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "layers" {
  for_each = toset(["bronze", "silver", "gold", "scripts"])
  bucket   = "${var.project}-${each.value}-${var.region}-${var.env}-${random_string.suffix.result}"
  tags     = var.tags
}

resource "aws_s3_bucket_versioning" "layers" {
  for_each = aws_s3_bucket.layers
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "layers" {
  for_each = aws_s3_bucket.layers
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "layers" {
  for_each                = aws_s3_bucket.layers
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
