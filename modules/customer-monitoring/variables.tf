# --- Identity & tagging ----------------------------------------------------------------

variable "customer_code" {
  description = "Customer code, e.g. \"cus001\". Used in alarm names and the Customer tag."
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. \"prod-cus001\". Used in resource names and the Environment tag."
  type        = string
}

variable "region" {
  description = "AWS region of this customer's resources"
  type        = string
}

variable "product" {
  description = "Product tag value"
  type        = string
  default     = "oglh-platform"
}

variable "cost_center" {
  description = "Cost Center tag value"
  type        = string
  default     = "unassigned"
}

# --- Alert delivery --------------------------------------------------------------------

variable "formatter_lambda_arn" {
  description = "ARN of the Slack formatter Lambda (alert-formatter module). Null means alerts are not sent to Slack."
  type        = string
  default     = null
}

variable "management_account_id" {
  description = "Account ID of the management account that hosts the formatter Lambda"
  type        = string
  default     = null
}

variable "engineering_alert_emails" {
  description = "Engineering emails for alert-delivery failures. These bypass Slack on purpose."
  type        = list(string)
  default     = []
}

variable "dashboard_url" {
  description = "Link to this customer's Grafana dashboard, shown in every alert"
  type        = string
  default     = null
}

# --- Grafana read-only access ----------------------------------------------------------

variable "grafana_account_id" {
  description = "AWS account ID Grafana runs in. Null skips the read-only role."
  type        = string
  default     = null
}

variable "grafana_external_id" {
  description = "External ID Grafana uses when assuming the read-only role"
  type        = string
  default     = null
  sensitive   = true
}

# --- Monitored resources (null skips the matching alarms) ------------------------------

variable "instance_id" {
  description = "Lighthouse EC2 instance ID. Null skips instance alarms. Needs detailed monitoring on."
  type        = string
  default     = null
}

variable "existing_ec2_role_name" {
  description = "IAM role already attached to the instance (e.g. \"ec2_role\"). Required if instance_id is set."
  type        = string
  default     = null
}

variable "mount_points" {
  description = "Disks to alarm on, keyed by a short name. Path, device and fstype must match what the CloudWatch agent reports."
  type = map(object({
    path   = string
    device = string
    fstype = string
  }))
  default = {
    root = { path = "/", device = "nvme0n1p1", fstype = "xfs" }
  }
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB. Null skips ALB alarms."
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the ALB target group. Required if alb_arn_suffix is set."
  type        = string
  default     = null
}

variable "nlb_arn_suffix" {
  description = "ARN suffix of the NLB. Null skips OpenVPN alarms."
  type        = string
  default     = null
}

variable "nlb_target_group_arn_suffix" {
  description = "ARN suffix of the OpenVPN target group. Required if nlb_arn_suffix is set."
  type        = string
  default     = null
}

variable "waf_web_acl_name" {
  description = "Name of the WAF Web ACL. Null skips the WAF alarm."
  type        = string
  default     = null
}

variable "waf_web_acl_region" {
  description = "Region of the Web ACL's metrics. Defaults to var.region."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN of the customer domain. Null skips certificate alarms."
  type        = string
  default     = null
}

variable "https_availability_canary_name" {
  description = "Name of the HTTPS canary (checks the customer domain every minute). Null skips the alarm."
  type        = string
  default     = null
}

variable "synthetics_canary_name" {
  description = "Name of the workflow canary (runs every 5 minutes). Null skips the alarm."
  type        = string
  default     = null
}

variable "backup_monitoring_enabled" {
  description = "Alarm when no daily AMI snapshot succeeds. Keep false until the snapshot job publishes its metric."
  type        = bool
  default     = false
}

# --- Thresholds (spec defaults) --------------------------------------------------------

variable "cpu_warning_threshold" {
  description = "CPU % for the P3 warning"
  type        = number
  default     = 70
}

variable "cpu_critical_threshold" {
  description = "CPU % for the P2 critical alarm"
  type        = number
  default     = 90
}

variable "memory_warning_threshold" {
  description = "Memory % for the P3 warning"
  type        = number
  default     = 70
}

variable "memory_critical_threshold" {
  description = "Memory % for the P2 critical alarm"
  type        = number
  default     = 85
}

variable "disk_warning_threshold" {
  description = "Disk % for the P3 warning"
  type        = number
  default     = 80
}

variable "disk_critical_threshold" {
  description = "Disk % for the P2 critical alarm"
  type        = number
  default     = 90
}

variable "alb_5xx_rate_threshold_percent" {
  description = "ALB 5xx error rate (%) for the P2 alarm"
  type        = number
  default     = 5
}

variable "alb_5xx_min_requests_per_minute" {
  description = "Minimum requests per minute before the 5xx rate is checked"
  type        = number
  default     = 50
}

variable "alb_latency_p95_threshold_seconds" {
  description = "ALB p95 response time (seconds) for the P2 alarm"
  type        = number
  default     = 0.3
}

variable "anomaly_band_width" {
  description = "Width of the anomaly detection band (request rate, egress, VPN, WAF alarms)"
  type        = number
  default     = 3
}

variable "acm_warning_days" {
  description = "Days left on the certificate for the P2 warning"
  type        = number
  default     = 30
}

variable "acm_critical_days" {
  description = "Days left on the certificate for the P1 alarm"
  type        = number
  default     = 7
}

# --- Cost monitoring -------------------------------------------------------------------

variable "monthly_budget_usd" {
  description = "Monthly budget in USD. 80% spent or forecast to exceed alerts P3; 100% spent alerts P2."
  type        = number
  default     = 500
}

variable "budget_notification_emails" {
  description = "Extra emails notified by AWS Budgets"
  type        = list(string)
  default     = []
}

variable "cost_anomaly_threshold_usd" {
  description = "Minimum cost anomaly (USD) that sends a P3 alert"
  type        = number
  default     = 100
}
