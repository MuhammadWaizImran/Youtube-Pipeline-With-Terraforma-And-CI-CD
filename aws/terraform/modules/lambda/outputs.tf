output "ingestion_function_name" {
  value = aws_lambda_function.ingestion.function_name
}

output "ingestion_function_arn" {
  value = aws_lambda_function.ingestion.arn
}

output "json_to_parquet_function_name" {
  value = aws_lambda_function.json_to_parquet.function_name
}

output "json_to_parquet_function_arn" {
  value = aws_lambda_function.json_to_parquet.arn
}

output "data_quality_function_name" {
  value = aws_lambda_function.data_quality.function_name
}

output "data_quality_function_arn" {
  value = aws_lambda_function.data_quality.arn
}
