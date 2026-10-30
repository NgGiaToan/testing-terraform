output "formatter_lambda_arn" {
  description = "ARN of the alert delivery Lambda in this region. Informational: customer accounts no longer need it, their alarms publish to the alert topics."
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

output "alerts_kms_key_arn" {
  description = "Customer-managed key that encrypts the alert and pipeline topics"
  value       = aws_kms_key.alerts.arn
}

output "pipeline_topic_arn" {
  description = "Topic for alarms on the alert delivery path itself. It delivers to the alert delivery Lambda, so those alarms reach Slack unless the Lambda itself is down"
  value       = aws_sns_topic.pipeline.arn
}

# DISABLED (the Grafana role is not used): see modules/alert-delivery/grafana.tf.
/*
output "grafana_role_arn" {
  description = "ARN of the read-only role to enter as `Assume Role ARN` in Grafana's management-account CloudWatch data source"
  value       = local.grafana_enabled ? aws_iam_role.grafana_read[0].arn : null
}
*/

output "slack_webhook_secret_arn" {
  description = "Secret holding this environment's Slack webhook URL(s): the one this module created, or the one passed in. Set its value with `aws secretsmanager put-secret-value`."
  value       = local.slack_webhook_secret_arn
}

# DISABLED (the IAM user is not used): see modules/alert-delivery/grafana.tf.
/*
output "grafana_user_name" {
  description = "IAM user with the read-only Grafana policy (null unless grafana_user_enabled). Make its access key with: aws iam create-access-key --user-name <this>, and enter it in the Grafana data source (Access & secret key)."
  value       = one(aws_iam_user.grafana_read[*].name)
}
*/
