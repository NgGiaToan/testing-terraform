# Service quotas (VPCs, Elastic IPs): 80%/95% usage, checked daily. Every customer gets a
# dedicated VPC (modules/customer-monitoring's design), so these quotas directly limit
# onboarding new customers. Requires "Monitor with CloudWatch" already turned on per quota
# in the Service Quotas console — see the service_quota_checks variable description.
resource "aws_cloudwatch_metric_alarm" "quota_warning" {
  for_each            = var.service_quota_checks
  alarm_name          = "${local.name_prefix}-${each.key}-quota-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 86400
  namespace           = "AWS/Usage"
  metric_name         = "ResourceCount"
  statistic           = "Maximum"
  threshold           = each.value.quota_limit * each.value.warning_threshold_pct / 100
  alarm_description   = "${each.key} usage above ${each.value.warning_threshold_pct}% of its quota"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
  dimensions          = each.value.dimensions
}

resource "aws_cloudwatch_metric_alarm" "quota_critical" {
  for_each            = var.service_quota_checks
  alarm_name          = "${local.name_prefix}-${each.key}-quota-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 86400
  namespace           = "AWS/Usage"
  metric_name         = "ResourceCount"
  statistic           = "Maximum"
  threshold           = each.value.quota_limit * each.value.critical_threshold_pct / 100
  alarm_description   = "${each.key} usage above ${each.value.critical_threshold_pct}% of its quota — new customer onboarding may soon be blocked"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
  dimensions          = each.value.dimensions
}
