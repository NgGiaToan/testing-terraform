output "formatter_lambda_arn" {
  description = "Pass to modules/customer-monitoring as formatter_lambda_arn for every customer in this region"
  value       = aws_lambda_function.formatter.arn
}

output "management_account_id" {
  description = "Pass to modules/customer-monitoring as management_account_id"
  value       = local.account_id
}

output "alert_topic_arns" {
  description = "Management-account priority topic ARNs keyed P1/P2/P3"
  value       = { for p, t in aws_sns_topic.alerts : p => t.arn }
}

output "pipeline_topic_arn" {
  description = "Topic for alarms on the alert delivery path itself (email to Engineering)"
  value       = aws_sns_topic.pipeline.arn
}

output "grafana_role_arn" {
  description = "ARN of the read-only role to enter as `Assume Role ARN` in Grafana's management-account CloudWatch data source"
  value       = local.grafana_enabled ? aws_iam_role.grafana_read[0].arn : null
}

output "slack_webhook_secret_arn" {
  description = "Secret holding the Slack webhook URL(s): the one this module created, or the one passed in. Set its value with `aws secretsmanager put-secret-value`."
  value       = local.slack_webhook_secret_arn
}
