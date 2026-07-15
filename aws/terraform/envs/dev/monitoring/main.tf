terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "monitoring" {
  source = "../../../modules/monitoring"

  project     = "yt-data-pipeline"
  env         = "dev"
  alert_email = var.alert_email

  tags = {
    project     = "yt-data-pipeline"
    environment = "dev"
    managed_by  = "terraform"
  }
}
