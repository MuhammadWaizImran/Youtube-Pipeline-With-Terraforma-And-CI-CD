output "database_names" {
  value = { for k, v in aws_glue_catalog_database.layers : k => v.name }
}

output "bronze_to_silver_job_name" {
  value = aws_glue_job.bronze_to_silver.name
}

output "silver_to_gold_job_name" {
  value = aws_glue_job.silver_to_gold.name
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.this.name
}

output "bronze_crawler_name" {
  value = aws_glue_crawler.bronze_statistics.name
}
