terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # One instance of this module = one environment (dev, stg, prd or a full name) in one region: its
  # own Lambda, role, secret and topics, named with the environment. The quota alarms are created in every
  # deployment: with several environments in one region each quota is alarmed once per environment, into its channels.
  shared_prefix = "lighthouse-alerting"
  name_prefix   = "${local.shared_prefix}-${var.environment}-${var.region}"
  priorities    = toset(["P1", "P2", "P3"])
  tags          = merge({ ManagedBy = "terraform", Component = "alert-delivery", Environment = var.environment }, var.tags)

  # Management-account alerts, same shape as modules/customer-monitoring/alerts.tf but with
  # no customer: alarm name is shared-<priority>-<environment>-<alert-key>. The "shared-" stands where
  # a customer code stands, so the name matches the topics' policy (*-P1-*, *-P2-*, *-P3-*); the
  # environment keeps it unique per environment in a region.
  alerts = {
    "firewall-drops" = {
      priority  = "P3", notify = ["Operations", "Engineering"], service = "Network Firewall", alert_type = "DroppedPackets"
      condition = "Shared Network Firewall dropped packets above their expected range (anomaly band width ${var.anomaly_band_width}) for 10 minutes"
    }
    "quota-80" = {
      priority  = "P3", notify = ["Operations", "Engineering"], service = "Service Quotas", alert_type = "QuotaUsagePercent"
      condition = "A management-account regional quota is above ${var.quota_warning_percent}% used"
    }
    "quota-95" = {
      priority  = "P2", notify = ["Operations", "Engineering"], service = "Service Quotas", alert_type = "QuotaUsagePercent"
      condition = "A management-account regional quota is above ${var.quota_critical_percent}% used — new customers cannot be provisioned"
    }
    "sns-failures" = {
      priority  = "P2", notify = ["Engineering"], service = "SNS", alert_type = "NumberOfNotificationsFailed"
      condition = "SNS could not deliver an alert notification to the alert delivery Lambda"
    }
    "lambda-errors" = {
      priority  = "P2", notify = ["Engineering"], service = "Lambda", alert_type = "Errors"
      condition = "The alert delivery Lambda returned an error — alerts may not reach Slack"
    }
    "lambda-throttles" = {
      priority  = "P2", notify = ["Engineering"], service = "Lambda", alert_type = "Throttles"
      condition = "The alert delivery Lambda was throttled — alerts are delayed or dropped"
    }
  }

  alarm_names = { for key, a in local.alerts : key => "shared-${a.priority}-${var.environment}-${key}" }

  alarm_descriptions = {
    for key, a in local.alerts : key => jsonencode({
      priority      = a.priority
      customer      = "shared"
      environment   = "management-${var.environment}"
      alert_type    = a.alert_type
      service       = a.service
      condition     = a.condition
      dashboard_url = var.dashboard_url == null ? "" : var.dashboard_url # not coalesce(): it skips ""
      notify        = a.notify
    })
  }
}
