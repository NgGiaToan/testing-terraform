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

variable "management_account_id" {
  description = "Account ID of the management account whose SNS topics receive this account's alarms (the alert-delivery stack). Null creates the alarms without notification actions."
  type        = string
  default     = null
}

variable "alert_topic_name_prefix" {
  description = "Name prefix of the management account's alert topics: <prefix>-<alert environment>-<region>-alerts-p1/p2/p3 (the alert environment is derived from `environment`, see sns.tf). Must match the alert-delivery module (its shared_prefix, lighthouse-alerting)."
  type        = string
  default     = "lighthouse-alerting"
}

variable "central_alert_topic_arns" {
  description = "Override: priority => ARN of the SNS topic that receives the alarms, e.g. {P1 = \"arn:...\", P2 = ..., P3 = ...}. Null (default) builds the ARNs from management_account_id, region, alert_topic_name_prefix and the alert environment derived from `environment`."
  type        = map(string)
  default     = null

  validation {
    condition     = var.central_alert_topic_arns == null || alltrue([for p in ["P1", "P2", "P3"] : contains(keys(var.central_alert_topic_arns), p)])
    error_message = "central_alert_topic_arns must have the keys P1, P2 and P3."
  }
}

variable "dashboard_url" {
  description = "Link to this customer's Grafana dashboard, shown in every alert"
  type        = string
  default     = null
}

# --- Grafana read-only access ----------------------------------------------------------

# DISABLED (the Grafana role is not used): see modules/customer-monitoring/grafana.tf.
/*
variable "grafana_account_id" {
  description = "AWS account ID Grafana runs in. Null skips the read-only role."
  type        = string
  default     = null
}
*/

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
  description = "ARN suffixes of the ALB target groups as a map of name => suffix (one entry is fine). Required if alb_arn_suffix is set. The alarms cover every group in the map: at most 8."
  type        = map(string)
  default     = null

  validation {
    condition     = var.alb_arn_suffix == null || (var.target_group_arn_suffix != null && length(var.target_group_arn_suffix) > 0)
    error_message = "target_group_arn_suffix is required (at least one entry) when alb_arn_suffix is set."
  }

  validation {
    condition     = var.target_group_arn_suffix == null || length(var.target_group_arn_suffix) <= 8
    error_message = "At most 8 target groups: each is a metric of the alarm, plus its combining expression, within the 10 CloudWatch allows."
  }
}

variable "nlb_arn_suffix" {
  description = "ARN suffix of the NLB. Null skips OpenVPN alarms."
  type        = string
  default     = null
}

variable "nlb_target_group_arn_suffix" {
  description = "ARN suffixes of the OpenVPN target groups as a map of name => suffix (one entry is fine). Required if nlb_arn_suffix is set. At most 8."
  type        = map(string)
  default     = null

  validation {
    condition     = var.nlb_arn_suffix == null || (var.nlb_target_group_arn_suffix != null && length(var.nlb_target_group_arn_suffix) > 0)
    error_message = "nlb_target_group_arn_suffix is required (at least one entry) when nlb_arn_suffix is set."
  }

  validation {
    condition     = var.nlb_target_group_arn_suffix == null || length(var.nlb_target_group_arn_suffix) <= 8
    error_message = "At most 8 target groups: each is a metric of the alarm, plus its combining expressions, within the 10 CloudWatch allows."
  }
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

# --- Enable flags: only needed when a value above is not known until apply -----------------
# Terraform must know at plan time whether a group of alarms exists, but an ID of a resource
# created in the same apply is only known after it. Set the flag (true or false, a value known
# at plan) and pass the unknown ID as usual. Null (default) = on when the value above is set.

variable "enable_instance_alarms" {
  description = "Turn the instance alarms and agent config on or off. Null = on when instance_id is set. Set it when instance_id comes from a resource created in the same apply."
  type        = bool
  default     = null
}

variable "enable_alb_alarms" {
  description = "Turn the ALB alarms on or off. Null = on when alb_arn_suffix is set. Set it when the ALB is created in the same apply."
  type        = bool
  default     = null
}

variable "enable_nlb_alarms" {
  description = "Turn the OpenVPN (NLB) alarms on or off. Null = on when nlb_arn_suffix is set. Set it when the NLB is created in the same apply."
  type        = bool
  default     = null
}

variable "enable_waf_alarm" {
  description = "Turn the WAF alarm on or off. Null = on when waf_web_acl_name is set. Set it when the Web ACL is created in the same apply."
  type        = bool
  default     = null
}

variable "enable_certificate_alarms" {
  description = "Turn the certificate alarms on or off. Null = on when acm_certificate_arn is set. Set it when the certificate is created in the same apply."
  type        = bool
  default     = null
}

variable "enable_https_canary_alarm" {
  description = "Turn the HTTPS canary alarm on or off. Null = on when https_availability_canary_name is set. Set it when the canary is created in the same apply."
  type        = bool
  default     = null
}

variable "enable_workflow_canary_alarm" {
  description = "Turn the workflow canary alarm on or off. Null = on when synthetics_canary_name is set. Set it when the canary is created in the same apply."
  type        = bool
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
