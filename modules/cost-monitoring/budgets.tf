# One monthly budget per customer, filtered by the customer's Instance tag. Not covered by the tag: costs
# that cannot carry one (some services, shared charges) belong to no customer.

resource "aws_budgets_budget" "customer" {
  for_each = var.customers

  name         = "${var.environment}-${each.key}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(each.value.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:%s$%s", var.cost_tag_key, each.value.instance)]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.warning_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [local.topic_warning]
  }

  dynamic "notification" {
    for_each = var.forecast_alert_enabled ? [1] : []
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = var.critical_percent
      threshold_type            = "PERCENTAGE"
      notification_type         = "FORECASTED"
      subscriber_sns_topic_arns = [local.topic_warning]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.critical_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [local.topic_critical]
  }

  tags = var.tags
}
