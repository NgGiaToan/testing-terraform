# Budget alerts. The spec's Cost Monitoring section ("visibility" and "budget alerts") is
# still to be defined; this keeps the existing per-customer budget and anomaly monitor and
# routes them by the spec's priority table: 80% of budget or a forecast to exceed → P3,
# 100% of budget → P2. Both filter by the Customer cost allocation tag (activate it in
# Billing > Cost Allocation Tags first, or they filter to zero spend).

resource "aws_budgets_budget" "customer" {
  name         = "${var.customer_code}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Customer$%s", var.customer_code)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts["P3"].arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts["P3"].arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts["P2"].arn]
  }
}

resource "aws_ce_anomaly_monitor" "customer" {
  name         = "${var.customer_code}-cost-anomaly-monitor"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    Tags = {
      Key          = "Customer"
      Values       = [var.customer_code]
      MatchOptions = ["EQUALS"]
    }
  })
}

resource "aws_ce_anomaly_subscription" "customer" {
  name             = "${var.customer_code}-cost-anomaly-subscription"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [aws_ce_anomaly_monitor.customer.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alerts["P3"].arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.cost_anomaly_threshold_usd)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
