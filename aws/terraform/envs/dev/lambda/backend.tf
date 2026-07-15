terraform {
  backend "s3" {
    key = "dev/lambda.tfstate"
  }
}
