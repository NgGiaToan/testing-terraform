terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Customer    = var.customer_code
    Environment = var.environment
    Product     = var.product
    CostCenter  = var.cost_center
    Region      = var.region
    ManagedBy   = "terraform"
  }

  name_prefix = "${var.environment}-monitoring"
  account_id  = data.aws_caller_identity.current.account_id

  # Each group of alarms is on when its enable_* flag says so. With no flag it is on when the
  # value is set. Set the flag when the value is only known after apply (the resource is
  # created in the same apply): `count` cannot depend on a value that is not known yet.
  instance_enabled        = var.enable_instance_alarms != null ? var.enable_instance_alarms : var.instance_id != null
  alb_enabled             = var.enable_alb_alarms != null ? var.enable_alb_alarms : var.alb_arn_suffix != null
  nlb_enabled             = var.enable_nlb_alarms != null ? var.enable_nlb_alarms : var.nlb_arn_suffix != null
  waf_enabled             = var.enable_waf_alarm != null ? var.enable_waf_alarm : var.waf_web_acl_name != null
  acm_enabled             = var.enable_certificate_alarms != null ? var.enable_certificate_alarms : var.acm_certificate_arn != null
  https_canary_enabled    = var.enable_https_canary_alarm != null ? var.enable_https_canary_alarm : var.https_availability_canary_name != null
  workflow_canary_enabled = var.enable_workflow_canary_alarm != null ? var.enable_workflow_canary_alarm : var.synthetics_canary_name != null

  # The target groups come in as { name = suffix }. Re-keyed as { tg1 = suffix, tg2 = ... } in the
  # order of the names: the keys are the metric IDs of the alarms that watch the groups, so one
  # alarm covers all of them and keeps its name. (Metric IDs cannot be the free-text names.)
  alb_target_groups = { for i, k in sort(keys(var.target_group_arn_suffix == null ? {} : var.target_group_arn_suffix)) : "tg${i + 1}" => var.target_group_arn_suffix[k] }
  nlb_target_groups = { for i, k in sort(keys(var.nlb_target_group_arn_suffix == null ? {} : var.nlb_target_group_arn_suffix)) : "tg${i + 1}" => var.nlb_target_group_arn_suffix[k] }
}
