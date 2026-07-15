variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "lambda_ingestion_role_arn" {
  type = string
}

variable "lambda_json_to_parquet_role_arn" {
  type = string
}

variable "lambda_dq_role_arn" {
  type = string
}

variable "ingestion_source_dir" {
  description = "Local path to lambdas/youtube_api_integstion"
  type        = string
}

variable "json_to_parquet_source_dir" {
  description = "Local path to lambdas/json_to_parquet"
  type        = string
}

variable "dq_source_dir" {
  description = "Local path to data_quality"
  type        = string
}

variable "bronze_bucket_name" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "youtube_regions" {
  type    = string
  default = "US,GB,CA,DE,FR,IN,JP,KR,MX,RU"
}

variable "youtube_api_key" {
  type      = string
  sensitive = true
}

variable "sns_topic_arn" {
  type = string
}

variable "silver_database" {
  type = string
}

variable "reference_table_name" {
  type    = string
  default = "clean_reference_data"
}

variable "dq_min_row_count" {
  type    = number
  default = 10
}

variable "dq_max_null_percent" {
  type    = number
  default = 5.0
}

# AWS SDK for pandas (awswrangler) managed Lambda layer — see
# https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html for the
# current ARN per region/Python version; default below is us-east-1 /
# Python 3.11.
variable "awswrangler_layer_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python311:28"
}

variable "tags" {
  type    = map(string)
  default = {}
}
