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
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "lighthouse-alerting"
  priorities  = toset(["P1", "P2", "P3"])
  tags        = merge({ ManagedBy = "terraform", Component = "alert-formatter" }, var.tags)

  # Management-account alerts, same shape as modules/customer-monitoring/alerts.tf but with
  # no customer: alarm name is <priority>-<alert-key>.
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
    "lambda-errors" = {
      priority  = "P2", notify = ["Engineering"], service = "Lambda", alert_type = "Errors"
      condition = "The alert formatter Lambda returned an error — alerts may not reach Slack"
    }
    "lambda-throttles" = {
      priority  = "P2", notify = ["Engineering"], service = "Lambda", alert_type = "Throttles"
      condition = "The alert formatter Lambda was throttled — alerts are delayed or dropped"
    }
    "quota-job-errors" = {
      priority  = "P2", notify = ["Engineering"], service = "Lambda", alert_type = "Errors"
      condition = "The quota publisher Lambda returned an error — quota alarms are no longer fed"
    }
  }

  alarm_names = { for key, a in local.alerts : key => "${a.priority}-${key}" }

  alarm_descriptions = {
    for key, a in local.alerts : key => jsonencode({
      priority      = a.priority
      customer      = "shared"
      alert_type    = a.alert_type
      service       = a.service
      condition     = a.condition
      dashboard_url = coalesce(var.dashboard_url, "")
      notify        = a.notify
    })
  }
}
