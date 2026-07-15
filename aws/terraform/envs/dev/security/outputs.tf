output "lambda_ingestion_role_arn" {
  value = module.security.lambda_ingestion_role_arn
}

output "lambda_json_to_parquet_role_arn" {
  value = module.security.lambda_json_to_parquet_role_arn
}

output "lambda_dq_role_arn" {
  value = module.security.lambda_dq_role_arn
}

output "glue_role_arn" {
  value = module.security.glue_role_arn
}

output "sfn_role_arn" {
  value = module.security.sfn_role_arn
}

output "eventbridge_role_arn" {
  value = module.security.eventbridge_role_arn
}
