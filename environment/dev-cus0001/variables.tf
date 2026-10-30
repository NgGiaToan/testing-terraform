variable "region" {
  description = "AWS region this environment is provisioned in"
  type        = string
  default     = "us-east-1"
}

# --- Alert delivery: the management-account alert delivery (output of environment/shr-monitoring) ---

variable "management_account_id" {
  description = "Account ID of the management account whose SNS topics receive this account's alarms (the same account that runs environment/shr-monitoring). Null creates the alarms without notification actions."
  type        = string
  default     = null
}

# --- What to monitor: each group is skipped while its value is null ---

variable "dashboard_url" {
  description = "Link to this customer's Grafana Environment Overview dashboard, shown in every alert."
  type        = string
  default     = null
}

variable "instance_id" {
  description = "Lighthouse EC2 instance ID. Null skips the instance alarms. Needs detailed monitoring on."
  type        = string
  default     = null
}

variable "existing_ec2_role_name" {
  description = "IAM role already attached to the instance. Required when instance_id is set."
  type        = string
  default     = null
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB, e.g. app/my-alb/50dc6c495c0c9188. Null skips the ALB alarms."
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "ARN suffixes of the ALB target groups as a map of name => suffix, e.g. { web = \"targetgroup/my-tg/73e2d6bc24d8a067\" } (one entry is fine, at most 8). Required when alb_arn_suffix is set."
  type        = map(string)
  default     = null
}

variable "nlb_arn_suffix" {
  description = "ARN suffix of the NLB. Null skips the OpenVPN alarms."
  type        = string
  default     = null
}

variable "nlb_target_group_arn_suffix" {
  description = "ARN suffixes of the OpenVPN target groups as a map of name => suffix (one entry is fine, at most 8). Required when nlb_arn_suffix is set."
  type        = map(string)
  default     = null
}

variable "waf_web_acl_name" {
  description = "Name of the WAF Web ACL. Null skips the WAF alarm."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN of the customer domain. Null skips the certificate alarms."
  type        = string
  default     = null
}

variable "https_availability_canary_name" {
  description = "Name of the HTTPS canary that checks the customer domain. Null skips the alarm."
  type        = string
  default     = null
}

variable "synthetics_canary_name" {
  description = "Name of the workflow canary. Null skips the alarm."
  type        = string
  default     = null
}

variable "backup_monitoring_enabled" {
  description = "Alarm when no daily AMI snapshot succeeds. Keep false until the snapshot job publishes its metric."
  type        = bool
  default     = false
}

# --- Grafana: read-only role for the internal Grafana (null skips the role) ---

# DISABLED (the Grafana role is not used): see modules/customer-monitoring/grafana.tf.
/*
variable "grafana_account_id" {
  description = "AWS account ID Grafana runs in (shown on the CloudWatch data source page of Grafana). Null skips the read-only role."
  type        = string
  default     = null
}
*/
