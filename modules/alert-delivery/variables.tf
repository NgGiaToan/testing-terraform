variable "region" {
  description = "Region where the alert delivery Lambda and the alert topics are deployed. Customer alarms in this region publish to these topics: deploy one stack per region that hosts customers."
  type        = string
}

variable "environment" {
  description = "Environment this instance serves: dev, stg or prd, or the full environment name for any other (e.g. demo-foo). It gets its own alert delivery Lambda, IAM role, Slack webhook secret and alert topics, so the alerts of the customer environments wired to it reach only its Slack channels. A customer environment of the same name publishes to these topics (customer-monitoring derives it from its own environment name). The wiring is by name only: the topic policy takes alarms from any account and does not check the environment."
  type        = string

  validation {
    # Longest name built from it: the formatter role, lighthouse-alerting-<environment>-<region>-formatter, within IAM's 64 characters.
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-13 characters: lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
}

variable "slack_webhook_secret_arn" {
  description = "ARN of an existing secret, in this region, that holds this environment's Slack webhook URLs as JSON, one per team: {\"Operations\": \"<url>\", \"Engineering\": \"<url>\"}. If null, the module creates an empty secret, lighthouse-alerting-<environment>-<region>-slack-webhooks. Set its value with the AWS CLI so the URL stays out of Terraform state."
  type        = string
  default     = null
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
  description = "Quotas to watch, keyed by a short name used in the alarm name. No Lambda measures anything: each one names a usage metric that AWS publishes itself, `AWS/Usage` `ResourceCount`, by its `dimensions` (exactly the dimensions of that metric, no more, no fewer). `limit` null divides the usage by SERVICE_QUOTA(), which follows the quota automatically but only works for services that integrate their usage metrics with Service Quotas (not AWS WAF, not Amazon VPC); a number divides by that fixed quota instead, so change it when the quota is raised. Quotas with no AWS/Usage metric (VPCs, Elastic IPs, and ALBs/NLBs until their metric is confirmed) cannot be watched here. NOT VERIFIED: that WAF's metric has only the Resource dimension, and that the metric exists in your account (it appears only when at least one such resource exists). Check in CloudWatch > Metrics > Usage > By AWS Resource, or with aws cloudwatch list-metrics --namespace AWS/Usage, before the first apply. Default: the four regional AWS WAF quotas (web ACLs, rule groups, IP sets, regex pattern sets)."
  type = map(object({
    dimensions = map(string)
    limit      = optional(number)
  }))
  default = {
    # AWS WAF, regional (CloudFront WAF is in us-east-1 only: add its Resource values there if needed). Limits are the
    # documented defaults (web ACLs L-2EC3DE7B, rule groups L-C5BCD850, IP sets L-D6DA96AE, regex pattern sets L-BF0029B0).
    waf-web-acls    = { dimensions = { Resource = "WebAclsPerAccountRegional" }, limit = 100 }
    waf-rule-groups = { dimensions = { Resource = "RuleGroupsPerAccountRegional" }, limit = 100 }
    waf-ip-sets     = { dimensions = { Resource = "IpSetsPerAccountRegional" }, limit = 100 }
    waf-regex-sets  = { dimensions = { Resource = "RegexPatternSetsPerAccountRegional" }, limit = 10 }
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

# DISABLED (the Grafana role is not used): see modules/alert-delivery/grafana.tf.
/*
variable "grafana_account_id" {
  description = "AWS account ID that Grafana runs in. Null skips the read-only role in this account."
  type        = string
  default     = null
}
*/

# DISABLED (the IAM user is not used): see modules/alert-delivery/grafana.tf.
/*
variable "grafana_user_enabled" {
  description = "Create an IAM user with the read-only Grafana policy (grafana.tf), for a Grafana server that has no AWS identity to assume a role from. No access key is created: make it by hand (aws iam create-access-key --user-name <grafana_user_name output>) and type it into the data source in the Grafana UI, so it never reaches the Terraform state. Turn it on in one deployment (the user can read every region)."
  type        = bool
  default     = false
}
*/
