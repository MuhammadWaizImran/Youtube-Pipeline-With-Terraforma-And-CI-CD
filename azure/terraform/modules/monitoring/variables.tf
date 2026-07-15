variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "alert_email" {
  description = "Email address to receive pipeline success/failure notifications (replaces the SNS email subscription)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
