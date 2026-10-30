variable "region" {
  description = "Region where the formatter Lambda is deployed. Customer topics in other regions must be listed in customer_regions."
  type        = string
}

variable "slack_webhook_secret_arn" {
  description = "ARN of an existing secret that holds the Slack webhook URL: one URL for all teams, or JSON like {\"Operations\": \"<url>\", \"Engineering\": \"<url>\"}. If null, the module creates an empty secret. Set its value with the AWS CLI so the URL stays out of Terraform state."
  type        = string
  default     = null
}

variable "customer_regions" {
  description = "Other regions where customers have alert topics that send to the formatter. Each account in customer_account_ids is allowed in these regions and in the module's own. Opt-in regions are handled automatically (see the AWS caveat in formatter.tf)."
  type        = list(string)
  default     = []
}

variable "customer_account_ids" {
  description = "Customer AWS account IDs allowed to send alerts to the formatter. Add one per customer at onboarding."
  type        = list(string)
  default     = []
}

variable "engineering_alert_emails" {
  description = "Engineering emails for the pipeline topic. Alarms on the alert path itself (Lambda errors and throttles, quota job) go out by email, because they must not depend on the formatter."
  type        = list(string)
  default     = []
}

variable "dashboard_url" {
  description = "Link to the Grafana Platform dashboard, shown in management-account alerts."
  type        = string
  default     = null
}

# --- Shared components -----------------------------------------------------------------

variable "network_firewall_name" {
  description = "Name of the shared Network Firewall. Null skips the dropped-packets alarm."
  type        = string
  default     = null
}

variable "network_firewall_availability_zones" {
  description = "Availability zones of the firewall endpoints, at most 4. The alarm sums DroppedPackets over all zones and both engines, and CloudWatch allows 10 metrics and expressions per alarm."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.network_firewall_availability_zones) <= 4
    error_message = "At most 4 availability zones: (zones x 2 engines) + the sum + the anomaly band must stay within 10 metrics."
  }
}

variable "anomaly_band_width" {
  description = "Width of the anomaly detection band for the firewall-drops alarm."
  type        = number
  default     = 3
}

variable "quotas" {
  description = "Management-account quotas to watch, keyed by the `Quota` metric dimension. `usage` picks the counter in quota_publisher.py (vpcs or elastic-ips). Defaults: VPCs per region and Elastic IPs."
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
  description = "Quota usage (%) above which the P3 alarm fires."
  type        = number
  default     = 80
}

variable "quota_critical_percent" {
  description = "Quota usage (%) above which the P2 alarm fires."
  type        = number
  default     = 95
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "grafana_account_id" {
  description = "AWS account ID that Grafana runs in. Null skips the read-only role in this account."
  type        = string
  default     = null
}

variable "grafana_external_id" {
  description = "External ID Grafana uses to assume the read-only role in this account."
  type        = string
  default     = null
  sensitive   = true
}
