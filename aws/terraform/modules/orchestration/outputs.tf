output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "schedule_rule_name" {
  value = aws_cloudwatch_event_rule.schedule.name
}
