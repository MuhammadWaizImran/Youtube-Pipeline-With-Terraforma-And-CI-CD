output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "log_group_name" {
  value = module.monitoring.log_group_name
}
