output "alert_topic_arns" {
  description = "Priority topic ARNs keyed P1/P2/P3"
  value       = { for p, t in aws_sns_topic.alerts : p => t.arn }
}

output "pipeline_topic_arn" {
  description = "Topic for alert-delivery failures (email to Engineering, independent of the formatter Lambda)"
  value       = aws_sns_topic.pipeline.arn
}

output "alarm_names" {
  description = "Alert key → alarm name (<customer>-<priority>-<alert-key>) for every alert in the catalogue"
  value       = local.alarm_names
}

output "cloudwatch_agent_config_ssm_parameter" {
  description = "SSM parameter holding the CloudWatch agent config (fetch it on instance boot with `amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:<name>`)"
  value       = local.instance_enabled ? aws_ssm_parameter.cloudwatch_agent_config[0].name : null
}

output "grafana_role_arn" {
  description = "ARN of the read-only role to enter as `Assume Role ARN` in this customer's Grafana CloudWatch data source"
  value       = local.grafana_enabled ? aws_iam_role.grafana_read[0].arn : null
}
