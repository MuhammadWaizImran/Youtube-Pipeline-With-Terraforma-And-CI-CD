terraform {
  backend "s3" {
    key = "dev/monitoring.tfstate"
  }
}
