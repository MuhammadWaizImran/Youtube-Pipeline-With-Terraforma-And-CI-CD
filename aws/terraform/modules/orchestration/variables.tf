variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "sfn_role_arn" {
  type = string
}

variable "eventbridge_role_arn" {
  type = string
}

variable "template_path" {
  description = "Path to aws/step_functions/pipeline_orchestration.tftpl"
  type        = string
}

variable "ingestion_function_arn" {
  type = string
}

variable "json_to_parquet_function_arn" {
  type = string
}

variable "data_quality_function_arn" {
  type = string
}

variable "bronze_to_silver_job_name" {
  type = string
}

variable "silver_to_gold_job_name" {
  type = string
}

variable "bronze_database" {
  type = string
}

variable "silver_database" {
  type = string
}

variable "gold_database" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "gold_bucket_name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "schedule_expression" {
  description = "EventBridge schedule — changing this touches ONLY this module's state"
  type        = string
  default     = "rate(6 hours)"
}

variable "schedule_enabled" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
