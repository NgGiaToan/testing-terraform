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
  description = "Region the formatter Lambda is deployed in. Customer topics in other regions deliver to it too when listed in customer_regions."
  type        = string
  default     = "ap-southeast-2"
}

variable "slack_webhook_secret_arn" {
  description = "ARN of an existing secret holding the Slack Incoming Webhook URL(s). Null (default) creates an empty secret, lighthouse-alerting-slack-webhooks; set its value with the AWS CLI after the first apply (value: one URL, or JSON {\"Operations\": \"<url>\", \"Engineering\": \"<url>\"})."
  type        = string
  default     = null
}

variable "customer_regions" {
  description = "Regions besides var.region where customer accounts have alert topics that deliver to the formatter (cross-region SNS to Lambda). Empty = same region only."
  type        = list(string)
  default     = []
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

variable "grafana_account_id" {
  description = "AWS account ID Grafana runs in. Null skips the management-account read-only role."
  type        = string
  default     = null
}

variable "grafana_external_id" {
  description = "External ID Grafana uses when assuming the management-account read-only role"
  type        = string
  default     = null
  sensitive   = true
}

module "alert_formatter" {
  source = "../../modules/alert-formatter"

  region                              = var.region
  slack_webhook_secret_arn            = var.slack_webhook_secret_arn
  customer_account_ids                = var.customer_account_ids
  customer_regions                    = var.customer_regions
  engineering_alert_emails            = var.engineering_alert_emails
  network_firewall_name               = var.network_firewall_name
  network_firewall_availability_zones = var.network_firewall_availability_zones
  dashboard_url                       = var.dashboard_url
  grafana_account_id                  = var.grafana_account_id
  grafana_external_id                 = var.grafana_external_id
}

output "slack_webhook_secret_arn" {
  description = "Secret to put the Slack webhook URL(s) into: aws secretsmanager put-secret-value --secret-id <this> --secret-string ..."
  value       = module.alert_formatter.slack_webhook_secret_arn
}

output "grafana_role_arn" {
  description = "Assume Role ARN for Grafana's management-account CloudWatch data source"
  value       = module.alert_formatter.grafana_role_arn
}

output "formatter_lambda_arn" {
  description = "Set as formatter_lambda_arn in each customer environment in this region"
  value       = module.alert_formatter.formatter_lambda_arn
}

output "management_account_id" {
  description = "Set as management_account_id in each customer environment"
  value       = module.alert_formatter.management_account_id
}
