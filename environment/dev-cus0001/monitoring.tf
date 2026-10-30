module "monitoring" {
  source = "../../modules/customer-monitoring"

  customer_code = local.customer_code
  environment   = local.environment
  region        = var.region
  cost_center   = local.cost_center

  # Alert delivery (the budget of this customer is in environment/shr-monitoring: cost_customers)
  management_account_id = var.management_account_id
  dashboard_url         = var.dashboard_url

  # What to monitor (null skips that group of alarms)
  instance_id                    = var.instance_id
  existing_ec2_role_name         = var.existing_ec2_role_name
  alb_arn_suffix                 = var.alb_arn_suffix
  target_group_arn_suffix        = var.target_group_arn_suffix
  nlb_arn_suffix                 = var.nlb_arn_suffix
  nlb_target_group_arn_suffix    = var.nlb_target_group_arn_suffix
  waf_web_acl_name               = var.waf_web_acl_name
  acm_certificate_arn            = var.acm_certificate_arn
  https_availability_canary_name = var.https_availability_canary_name
  synthetics_canary_name         = var.synthetics_canary_name
  backup_monitoring_enabled      = var.backup_monitoring_enabled
}

# DISABLED (the Grafana role is not used): see modules/customer-monitoring/grafana.tf.
/*
output "grafana_role_arn" {
  description = "Assume Role ARN for this customer's Grafana CloudWatch data source (null while the Grafana variables are not set)"
  value       = module.monitoring.grafana_role_arn
}
*/
