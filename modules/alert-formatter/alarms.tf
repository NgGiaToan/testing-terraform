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

data "archive_file" "quota_publisher" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/quota_publisher.py"
  output_path = "${path.module}/lambda_src/quota_publisher.zip"
}

resource "aws_iam_role" "quota_publisher" {
  name               = "${local.name_prefix}-quota-publisher"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "quota_publisher" {
  statement {
    sid    = "ReadUsageAndQuotas"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeAddresses",
      "servicequotas:GetServiceQuota",
      "servicequotas:GetAWSDefaultServiceQuota",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PublishQuotaMetric"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Lighthouse/Quotas"]
    }
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.quota_publisher.arn}:*"]
  }
}

resource "aws_iam_role_policy" "quota_publisher" {
  name   = "${local.name_prefix}-quota-publisher"
  role   = aws_iam_role.quota_publisher.id
  policy = data.aws_iam_policy_document.quota_publisher.json
}

resource "aws_cloudwatch_log_group" "quota_publisher" {
  name              = "/aws/lambda/${local.name_prefix}-quota-publisher"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_lambda_function" "quota_publisher" {
  function_name    = "${local.name_prefix}-quota-publisher"
  role             = aws_iam_role.quota_publisher.arn
  handler          = "quota_publisher.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.quota_publisher.output_path
  source_code_hash = data.archive_file.quota_publisher.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      QUOTAS = jsonencode([for name, q in var.quotas : merge(q, { name = name })])
    }
  }

  depends_on = [aws_cloudwatch_log_group.quota_publisher, aws_iam_role_policy.quota_publisher]
}

# Every 5 minutes, to match the alarm period: with missing data treated as not breaching, a
# sparser schedule would let an alarm flap to OK between datapoints.
resource "aws_cloudwatch_event_rule" "quota_publisher" {
  name                = "${local.name_prefix}-quota-publisher"
  schedule_expression = "rate(5 minutes)"
  tags                = local.tags
}

resource "aws_cloudwatch_event_target" "quota_publisher" {
  rule = aws_cloudwatch_event_rule.quota_publisher.name
  arn  = aws_lambda_function.quota_publisher.arn
}

resource "aws_lambda_permission" "quota_publisher" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quota_publisher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.quota_publisher.arn
}

# Missing data is "not breaching" — the job's own Errors alarm covers a stopped job.
resource "aws_cloudwatch_metric_alarm" "quota_warning" {
  for_each            = var.quotas
  alarm_name          = "${local.alarm_names["quota-80"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["quota-80"]
  namespace           = "Lighthouse/Quotas"
  metric_name         = "QuotaUsagePercent"
  dimensions          = { Quota = each.key }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.quota_warning_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["quota-80"]
  ok_actions          = local.alarm_actions["quota-80"]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "quota_critical" {
  for_each            = var.quotas
  alarm_name          = "${local.alarm_names["quota-95"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["quota-95"]
  namespace           = "Lighthouse/Quotas"
  metric_name         = "QuotaUsagePercent"
  dimensions          = { Quota = each.key }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.quota_critical_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["quota-95"]
  ok_actions          = local.alarm_actions["quota-95"]
  tags                = local.tags
}

# --- Alert delivery path ---------------------------------------------------------------
# These go to the pipeline topic (email), not through the Lambda they watch.

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

resource "aws_cloudwatch_metric_alarm" "quota_job_errors" {
  alarm_name          = local.alarm_names["quota-job-errors"]
  alarm_description   = local.alarm_descriptions["quota-job-errors"]
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.quota_publisher.function_name }
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
