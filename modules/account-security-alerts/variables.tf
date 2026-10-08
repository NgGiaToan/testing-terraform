# Account-wide: GuardDuty, Security Hub, IAM Access Analyzer, and service quotas have no
# Customer/Environment scope, unlike modules/customer-monitoring — apply this module once
# per account, not once per customer.

variable "slack_bot_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Slack bot token (chat.postMessage). Null skips Slack delivery — the SNS topic is still created either way."
  type        = string
  default     = null
}

variable "slack_channel" {
  description = "Slack channel for account-level security/capacity alerts (Platform Ops + Engineering audience — these findings have no customer field to split on)"
  type        = string
  default     = null
}

variable "guardduty_high_severity_threshold" {
  description = "GuardDuty finding severity (0-10) at/above which an alert is High (spec: 7.0+)"
  type        = number
  default     = 7.0
}

variable "guardduty_medium_severity_threshold" {
  description = "GuardDuty finding severity (0-10) at/above which an alert is Medium (spec: 4.0-6.9)"
  type        = number
  default     = 4.0
}

variable "enable_security_hub_alerts" {
  description = "Whether to create the Security Hub EventBridge rule. Requires Security Hub already enabled in this account/region."
  type        = bool
  default     = true
}

variable "enable_access_analyzer_alerts" {
  description = "Whether to create the IAM Access Analyzer EventBridge rule. Requires an analyzer already created in this account/region."
  type        = bool
  default     = true
}

variable "service_quota_checks" {
  description = <<-EOT
    Per-quota usage alarms, keyed by a short name. Each entry needs the exact CloudWatch
    "AWS/Usage" dimensions AWS publishes for that quota — these only exist once "Monitor
    with CloudWatch" is turned on for that specific quota (Service Quotas console, per
    quota; Terraform has no resource to toggle this). Confirm the real dimensions via
    `aws cloudwatch list-metrics --namespace AWS/Usage` after enabling it, before trusting
    the defaults below — they're best-known values, not verified against a live account.
  EOT
  type = map(object({
    dimensions             = map(string)
    quota_limit            = number
    warning_threshold_pct  = optional(number, 80)
    critical_threshold_pct = optional(number, 95)
  }))
  default = {}
}
