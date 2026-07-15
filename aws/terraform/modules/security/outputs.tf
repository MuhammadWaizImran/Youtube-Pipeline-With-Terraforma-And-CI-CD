output "lambda_ingestion_role_arn" {
  value = aws_iam_role.lambda_ingestion.arn
}

output "lambda_json_to_parquet_role_arn" {
  value = aws_iam_role.lambda_json_to_parquet.arn
}

output "lambda_dq_role_arn" {
  value = aws_iam_role.lambda_dq.arn
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "sfn_role_arn" {
  value = aws_iam_role.sfn.arn
}

output "eventbridge_role_arn" {
  value = aws_iam_role.eventbridge.arn
}
