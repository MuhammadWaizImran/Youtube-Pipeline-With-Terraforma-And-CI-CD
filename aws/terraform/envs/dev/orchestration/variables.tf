variable "tfstate_bucket" {
  type = string
}

variable "tfstate_dynamodb_table" {
  type = string
}

variable "tfstate_region" {
  type    = string
  default = "us-east-1"
}

variable "schedule_expression" {
  type    = string
  default = "rate(6 hours)"
}

variable "schedule_enabled" {
  type    = bool
  default = false
}
