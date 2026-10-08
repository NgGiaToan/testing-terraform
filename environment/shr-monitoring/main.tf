terraform {
  required_version = ">= 1.10.0"

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

  # Management-account alerting (Slack formatter Lambda, shared-component alarms). Same
  # convention as shr-iam/shr-backup-dr: account-level, rarely changes, applied manually by
  # an admin — not from CI. One module call per region that hosts customers.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-monitoring/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Region this alerting stack serves (customer topics deliver to a Lambda in the same region)"
  type        = string
  default     = "us-east-1"
}

variable "slack_bot_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Slack bot token. Required — create the secret first (value: the xoxb- bot token)."
  type        = string
}

variable "slack_channel_operations" {
  description = "Slack channel for alerts addressed to Operations. Placeholder pending the real channel name."
  type        = string
  default     = "lighthouse-ops-alerts"
}

variable "slack_channel_engineering" {
  description = "Slack channel for alerts addressed to Engineering. Placeholder pending the real channel name."
  type        = string
  default     = "lighthouse-eng-alerts"
}

variable "customer_account_ids" {
  description = "Customer account IDs allowed to deliver alerts to the formatter. Add one per customer account at onboarding."
  type        = list(string)
  default     = []
}

variable "engineering_alert_emails" {
  description = "Engineering emails for alarms on the alert delivery path itself (Lambda errors/throttles, quota job)"
  type        = list(string)
  default     = []
}

variable "network_firewall_name" {
  description = "Shared Network Firewall in the Management VPC. Null skips the dropped-packets alarm."
  type        = string
  default     = null
}

variable "network_firewall_availability_zones" {
  description = "Availability zones the firewall has endpoints in (at most 4)"
  type        = list(string)
  default     = []
}

variable "dashboard_url" {
  description = "Grafana Platform dashboard URL included in management-account alerts"
  type        = string
  default     = null
}

module "alert_formatter" {
  source = "../../modules/alert-formatter"

  region                              = var.region
  slack_bot_token_secret_arn          = var.slack_bot_token_secret_arn
  slack_channel_operations            = var.slack_channel_operations
  slack_channel_engineering           = var.slack_channel_engineering
  customer_account_ids                = var.customer_account_ids
  engineering_alert_emails            = var.engineering_alert_emails
  network_firewall_name               = var.network_firewall_name
  network_firewall_availability_zones = var.network_firewall_availability_zones
  dashboard_url                       = var.dashboard_url
}

output "formatter_lambda_arn" {
  description = "Set as formatter_lambda_arn in each customer environment in this region"
  value       = module.alert_formatter.formatter_lambda_arn
}

output "management_account_id" {
  description = "Set as management_account_id in each customer environment"
  value       = module.alert_formatter.management_account_id
}
