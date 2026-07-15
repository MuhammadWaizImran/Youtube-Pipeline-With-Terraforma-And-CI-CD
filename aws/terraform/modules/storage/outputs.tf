output "bucket_names" {
  value = { for k, v in aws_s3_bucket.layers : k => v.bucket }
}

output "bucket_arns" {
  value = { for k, v in aws_s3_bucket.layers : k => v.arn }
}
