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
