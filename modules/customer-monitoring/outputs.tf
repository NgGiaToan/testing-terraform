output "alert_topic_arns" {
  description = "Priority => ARN of the management-account topic this account's alarms publish to (empty when no management_account_id is set)"
  value       = local.central_alert_topic_arns
}

output "alarm_names" {
  description = "Alert key → alarm name (<customer>-<priority>-<alert environment>-<alert-key>) for every alert in the catalogue"
  value       = local.alarm_names
}

output "cloudwatch_agent_config_ssm_parameter" {
  description = "SSM parameter holding the CloudWatch agent config (fetch it on instance boot with `amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:<name>`)"
  value       = local.instance_enabled ? aws_ssm_parameter.cloudwatch_agent_config[0].name : null
}

# DISABLED (the Grafana role is not used): see modules/customer-monitoring/grafana.tf.
/*
output "grafana_role_arn" {
  description = "ARN of the read-only role to enter as `Assume Role ARN` in this customer's Grafana CloudWatch data source"
  value       = local.grafana_enabled ? aws_iam_role.grafana_read[0].arn : null
}
*/
