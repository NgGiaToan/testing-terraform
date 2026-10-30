# Management-account alarms: the shared Network Firewall, regional quotas, and the alert
# delivery path itself. Names, priorities and descriptions come from local.alerts (main.tf).

locals {
  alarm_actions = {
    for key, a in local.alerts : key => [aws_sns_topic.alerts[a.priority].arn]
  }

  firewall_metrics = var.network_firewall_name == null ? {} : {
    for pair in setproduct(var.network_firewall_availability_zones, ["Stateful", "Stateless"]) :
    "m${index(var.network_firewall_availability_zones, pair[0]) * 2 + (pair[1] == "Stateful" ? 1 : 2)}" => {
      az     = pair[0]
      engine = pair[1]
    }
  }
}

# --- Shared Network Firewall -----------------------------------------------------------

# One firewall serves every customer. DroppedPackets is published per availability zone and
# engine, so the alarm sums them with explicit metric math (FILL keeps a quiet zone from
# erasing the sum) and compares the total to an anomaly band. Throttled packets are not
# included in DroppedPackets.
resource "aws_cloudwatch_metric_alarm" "firewall_drops" {
  count               = var.network_firewall_name != null && length(var.network_firewall_availability_zones) > 0 ? 1 : 0
  alarm_name          = local.alarm_names["firewall-drops"]
  alarm_description   = local.alarm_descriptions["firewall-drops"]
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold_metric_id = "band"
  comparison_operator = "GreaterThanUpperThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["firewall-drops"]
  ok_actions          = local.alarm_actions["firewall-drops"]
  tags                = local.tags

  dynamic "metric_query" {
    for_each = local.firewall_metrics
    content {
      id = metric_query.key
      metric {
        namespace   = "AWS/NetworkFirewall"
        metric_name = "DroppedPackets"
        dimensions = {
          FirewallName     = var.network_firewall_name
          AvailabilityZone = metric_query.value.az
          Engine           = metric_query.value.engine
        }
        stat   = "Sum"
        period = 300
      }
    }
  }

  metric_query {
    id          = "total"
    expression  = join("+", [for id in sort(keys(local.firewall_metrics)) : "FILL(${id},0)"])
    label       = "DroppedPackets (all zones, both engines)"
    return_data = true
  }

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(total, ${var.anomaly_band_width})"
    label       = "DroppedPackets (expected range)"
    return_data = true
  }
}

# --- Regional quotas -------------------------------------------------------------------
# Usage comes from the AWS/Usage metrics that AWS publishes itself, so nothing here publishes a metric (no Lambda).
# The alarm turns the count into a percentage with metric math: SERVICE_QUOTA(usage) when var.quotas has no limit
# (the service integrates its usage metrics with Service Quotas), else usage / limit. var.quotas holds the
# AWS/Usage dimensions of each quota.

# Missing data is "not breaching": a usage metric with no datapoints (none of that resource exists) is not an alert.
resource "aws_cloudwatch_metric_alarm" "quota_warning" {
  for_each            = var.quotas
  alarm_name          = "${local.alarm_names["quota-80"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["quota-80"]
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.quota_warning_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["quota-80"]
  ok_actions          = local.alarm_actions["quota-80"]
  tags                = local.tags

  metric_query {
    id          = "usage"
    return_data = false

    metric {
      namespace   = "AWS/Usage"
      metric_name = "ResourceCount"
      period      = 300
      stat        = "Maximum"
      dimensions  = each.value.dimensions
    }
  }

  metric_query {
    id          = "pct"
    expression  = each.value.limit == null ? "usage / SERVICE_QUOTA(usage) * 100" : "usage / ${each.value.limit} * 100"
    label       = "QuotaUsagePercent"
    return_data = true
  }
}

resource "aws_cloudwatch_metric_alarm" "quota_critical" {
  for_each            = var.quotas
  alarm_name          = "${local.alarm_names["quota-95"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["quota-95"]
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.quota_critical_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["quota-95"]
  ok_actions          = local.alarm_actions["quota-95"]
  tags                = local.tags

  metric_query {
    id          = "usage"
    return_data = false

    metric {
      namespace   = "AWS/Usage"
      metric_name = "ResourceCount"
      period      = 300
      stat        = "Maximum"
      dimensions  = each.value.dimensions
    }
  }

  metric_query {
    id          = "pct"
    expression  = each.value.limit == null ? "usage / SERVICE_QUOTA(usage) * 100" : "usage / ${each.value.limit} * 100"
    label       = "QuotaUsagePercent"
    return_data = true
  }
}

# --- Alert delivery path ---------------------------------------------------------------
# These go to the pipeline topic, which delivers to the same alert delivery Lambda (formatter.tf). Known
# limit: if that Lambda is down, lambda-errors and lambda-throttles cannot reach Slack through it.

# Delivery failures on each alert topic (alarms of every account arrive here).
resource "aws_cloudwatch_metric_alarm" "sns_failures" {
  for_each            = local.priorities
  alarm_name          = "${local.alarm_names["sns-failures"]}-${lower(each.key)}"
  alarm_description   = local.alarm_descriptions["sns-failures"]
  namespace           = "AWS/SNS"
  metric_name         = "NumberOfNotificationsFailed"
  dimensions          = { TopicName = aws_sns_topic.alerts[each.key].name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline.arn]
  ok_actions          = [aws_sns_topic.pipeline.arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = local.alarm_names["lambda-errors"]
  alarm_description   = local.alarm_descriptions["lambda-errors"]
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.formatter.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline.arn]
  ok_actions          = [aws_sns_topic.pipeline.arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = local.alarm_names["lambda-throttles"]
  alarm_description   = local.alarm_descriptions["lambda-throttles"]
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = aws_lambda_function.formatter.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.pipeline.arn]
  ok_actions          = [aws_sns_topic.pipeline.arn]
  tags                = local.tags
}
