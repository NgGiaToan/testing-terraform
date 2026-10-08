output "security_alerts_topic_arn" {
  description = "SNS topic ARN for account-level security/capacity alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "security_notifier_function_name" {
  description = "Lambda function name for the Slack notifier, null if Slack delivery isn't configured"
  value       = local.slack_enabled ? aws_lambda_function.security_notifier[0].function_name : null
}
