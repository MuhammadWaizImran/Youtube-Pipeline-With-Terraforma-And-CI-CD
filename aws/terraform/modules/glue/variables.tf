variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "glue_role_arn" {
  type = string
}

variable "scripts_bucket_name" {
  type = string
}

variable "bronze_bucket_name" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "gold_bucket_name" {
  type = string
}

variable "bronze_to_silver_script_path" {
  description = "Local path to glue_jobs/bronze_to_silver_statistics.py"
  type        = string
}

variable "silver_to_gold_script_path" {
  description = "Local path to glue_jobs/silver_to_gold_analytics.py"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
