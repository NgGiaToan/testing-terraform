# One cost anomaly monitor per customer, on the same Instance tag as the budget. An anomaly at or above the
# threshold is sent immediately to the P3 topic. The tag has to be active in Billing, and a monitor needs a few
# days of history before it can tell what is unusual.

resource "aws_ce_anomaly_monitor" "customer" {
  for_each = var.customers

  name         = "${var.environment}-${each.key}-cost-anomaly-monitor"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    Tags = {
      Key          = var.cost_tag_key
      Values       = [each.value.instance]
      MatchOptions = ["EQUALS"]
    }
  })

  tags = var.tags
}

resource "aws_ce_anomaly_subscription" "customer" {
  for_each = var.customers

  name             = "${var.environment}-${each.key}-cost-anomaly-subscription"
  frequency        = "IMMEDIATE" # an SNS subscriber needs IMMEDIATE
  monitor_arn_list = [aws_ce_anomaly_monitor.customer[each.key].arn]

  subscriber {
    type    = "SNS"
    address = local.topic_warning
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(coalesce(each.value.anomaly_threshold_usd, var.default_anomaly_threshold_usd))]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = var.tags
}
