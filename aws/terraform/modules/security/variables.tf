variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "bronze_bucket_arn" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "gold_bucket_arn" {
  type = string
}

variable "scripts_bucket_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
