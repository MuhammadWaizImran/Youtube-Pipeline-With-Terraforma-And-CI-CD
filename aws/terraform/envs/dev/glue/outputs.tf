output "database_names" {
  value = module.glue.database_names
}

output "bronze_to_silver_job_name" {
  value = module.glue.bronze_to_silver_job_name
}

output "silver_to_gold_job_name" {
  value = module.glue.silver_to_gold_job_name
}

output "athena_workgroup_name" {
  value = module.glue.athena_workgroup_name
}
