variable "region" {
  description = "Region this instance of the module serves. A customer's SNS topics can only deliver to a Lambda in the same region, so deploy one instance per region that hosts customers."
  type        = string
}

variable "slack_bot_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Slack bot token (chat.postMessage)"
  type        = string
}

variable "slack_channel_operations" {
  description = "Slack channel for alerts addressed to Operations"
  type        = string
}

variable "slack_channel_engineering" {
  description = "Slack channel for alerts addressed to Engineering. May equal the Operations channel."
  type        = string
}

variable "customer_account_ids" {
  description = "AWS account IDs of the customer accounts whose priority topics may invoke the formatter (the Lambda's resource policy). Add an account here when onboarding a customer."
  type        = list(string)
  default     = []
}

variable "engineering_alert_emails" {
  description = "Engineering emails subscribed to the pipeline topic. Pipeline alarms (Lambda errors/throttles, quota job) must not depend on the formatter Lambda, so they go out by email."
  type        = list(string)
  default     = []
}

variable "dashboard_url" {
  description = "Link to the Grafana Platform dashboard, included in management-account alerts"
  type        = string
  default     = null
}

# --- Shared components -----------------------------------------------------------------

variable "network_firewall_name" {
  description = "Name of the shared Network Firewall in the Management VPC. Null skips the dropped-packets alarm."
  type        = string
  default     = null
}

variable "network_firewall_availability_zones" {
  description = "Availability zones the firewall has endpoints in. DroppedPackets is summed over every zone and both engines in one alarm, and CloudWatch allows at most 10 metrics and expressions per alarm, so at most 4 zones."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.network_firewall_availability_zones) <= 4
    error_message = "At most 4 availability zones: (zones x 2 engines) + the sum + the anomaly band must stay within 10 metrics."
  }
}

variable "anomaly_band_width" {
  description = "Width of the anomaly detection band on the firewall-drops alarm"
  type        = number
  default     = 3
}

variable "quotas" {
  description = "Regional quotas of the management account to watch, keyed by the `Quota` metric dimension. `usage` selects the counter in quota_publisher.py (vpcs, elastic-ips). Defaults are the VPCs-per-region and EC2-VPC Elastic IPs quotas."
  type = map(object({
    service_code = string
    quota_code   = string
    usage        = string
  }))
  default = {
    vpcs        = { service_code = "vpc", quota_code = "L-F678F1CE", usage = "vpcs" }
    elastic-ips = { service_code = "ec2", quota_code = "L-0263D0A3", usage = "elastic-ips" }
  }
}

variable "quota_warning_percent" {
  description = "QuotaUsagePercent above which the P3 alarm fires"
  type        = number
  default     = 80
}

variable "quota_critical_percent" {
  description = "QuotaUsagePercent above which the P2 alarm fires"
  type        = number
  default     = 95
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
