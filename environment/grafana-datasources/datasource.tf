# How Grafana signs in to AWS is var.authentication_provider. Chosen here: "default" (AWS SDK Default): the
# Grafana server uses the AWS identity it already has (the role of its machine or task) and assumes the
# read-only role from it. On Grafana Cloud it would be "grafana_assume_role".
#
# CloudWatch of each customer account: one data source per entry of var.customers. Each assumes the
# read-only role that modules/customer-monitoring creates in that account when grafana_account_id is set
# (the account Grafana runs in). The dashboards list these data sources in their Customer dropdown and name
# none of them. A new customer is one more entry in var.customers.
locals {
  customer_role_arns = {
    for name, c in var.customers :
    name => c.role_arn != null ? c.role_arn : "arn:aws:iam::${c.account_id}:role/${c.environment}-monitoring-grafana-read"
  }
}

resource "grafana_data_source" "customer" {
  for_each = var.customers

  type = "cloudwatch"
  name = each.key
  uid  = "lighthouse-cw-${each.key}"

  json_data_encoded = jsonencode({
    authType      = var.authentication_provider
    assumeRoleArn = local.customer_role_arns[each.key]
    defaultRegion = each.value.region
  })
}

# CloudWatch of the management account, through the read-only role of modules/alert-delivery. Only
# when management_grafana_role_arn is set. Its uid is the one environment/grafana-alerting reads.
resource "grafana_data_source" "cloudwatch_management" {
  count = var.management_grafana_role_arn == null ? 0 : 1

  type = "cloudwatch"
  name = "CloudWatch - management account"
  uid  = "lighthouse-cw-management"

  json_data_encoded = jsonencode({
    authType      = var.authentication_provider
    assumeRoleArn = var.management_grafana_role_arn
    defaultRegion = var.region
  })
}
