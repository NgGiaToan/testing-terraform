# Performance & capacity, plus platform health (backups, alert delivery). Name, SNS topic
# and description come from local.alerts (alerts.tf).

# --- Instance: CPU, memory, disk -------------------------------------------------------

# Needs detailed monitoring on the instance for one-minute datapoints.
resource "aws_cloudwatch_metric_alarm" "cpu_warning" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["cpu-warning"]
  alarm_description   = local.alarm_descriptions["cpu-warning"]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 15
  datapoints_to_alarm = 15
  threshold           = var.cpu_warning_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["cpu-warning"]
  ok_actions          = local.alarm_actions["cpu-warning"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_critical" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["cpu-critical"]
  alarm_description   = local.alarm_descriptions["cpu-critical"]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = var.cpu_critical_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["cpu-critical"]
  ok_actions          = local.alarm_actions["cpu-critical"]
  tags                = local.common_tags
}

# Missing memory data is "not breaching" here; a dead agent is caught by agent-heartbeat.
resource "aws_cloudwatch_metric_alarm" "memory_warning" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["memory-warning"]
  alarm_description   = local.alarm_descriptions["memory-warning"]
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 15
  datapoints_to_alarm = 15
  threshold           = var.memory_warning_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["memory-warning"]
  ok_actions          = local.alarm_actions["memory-warning"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_critical" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["memory-critical"]
  alarm_description   = local.alarm_descriptions["memory-critical"]
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = var.memory_critical_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["memory-critical"]
  ok_actions          = local.alarm_actions["memory-critical"]
  tags                = local.common_tags
}

# One warning and one critical alarm per mount point in var.mount_points.
resource "aws_cloudwatch_metric_alarm" "disk_warning" {
  for_each            = local.instance_enabled ? var.mount_points : {}
  alarm_name          = "${local.alarm_names["disk-warning"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["disk-warning"]
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = var.instance_id, path = each.value.path, device = each.value.device, fstype = each.value.fstype }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = var.disk_warning_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["disk-warning"]
  ok_actions          = local.alarm_actions["disk-warning"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "disk_critical" {
  for_each            = local.instance_enabled ? var.mount_points : {}
  alarm_name          = "${local.alarm_names["disk-critical"]}-${each.key}"
  alarm_description   = local.alarm_descriptions["disk-critical"]
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = var.instance_id, path = each.value.path, device = each.value.device, fstype = each.value.fstype }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = var.disk_critical_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["disk-critical"]
  ok_actions          = local.alarm_actions["disk-critical"]
  tags                = local.common_tags
}

# --- ALB performance -------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count               = local.alb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["alb-latency"]
  alarm_description   = local.alarm_descriptions["alb-latency"]
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = var.alb_latency_p95_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["alb-latency"]
  ok_actions          = local.alarm_actions["alb-latency"]
  tags                = local.common_tags
}

# Counts only requests for which the load balancer chose a target.
resource "aws_cloudwatch_metric_alarm" "alb_request_rate" {
  count               = local.alb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["alb-request-rate"]
  alarm_description   = local.alarm_descriptions["alb-request-rate"]
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold_metric_id = "band"
  comparison_operator = "GreaterThanUpperThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["alb-request-rate"]
  ok_actions          = local.alarm_actions["alb-request-rate"]
  tags                = local.common_tags

  metric_query {
    id          = "requests"
    return_data = true
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(requests, ${var.anomaly_band_width})"
    label       = "RequestCount (expected range)"
    return_data = true
  }
}

# Counts all outbound bytes, including web and VPN responses. Anomaly bands need about two
# weeks of history to be accurate.
resource "aws_cloudwatch_metric_alarm" "network_egress" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["network-egress"]
  alarm_description   = local.alarm_descriptions["network-egress"]
  evaluation_periods  = 6
  datapoints_to_alarm = 6
  threshold_metric_id = "band"
  comparison_operator = "GreaterThanUpperThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["network-egress"]
  ok_actions          = local.alarm_actions["network-egress"]
  tags                = local.common_tags

  metric_query {
    id          = "out"
    return_data = true
    metric {
      namespace   = "AWS/EC2"
      metric_name = "NetworkOut"
      dimensions  = { InstanceId = var.instance_id }
      stat        = "Sum"
      period      = 300
    }
  }

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(out, ${var.anomaly_band_width})"
    label       = "NetworkOut (expected range)"
    return_data = true
  }
}

# Missing data would look healthy, so a silent agent is treated as breaching — otherwise
# the memory and disk alarms above would stop working without anyone noticing.
resource "aws_cloudwatch_metric_alarm" "agent_heartbeat" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["agent-heartbeat"]
  alarm_description   = local.alarm_descriptions["agent-heartbeat"]
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "SampleCount"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["agent-heartbeat"]
  ok_actions          = local.alarm_actions["agent-heartbeat"]
  tags                = local.common_tags
}

# --- Platform health -------------------------------------------------------------------

# Custom metric published by the daily AMI snapshot job. 25 consecutive one-hour periods
# with no success = no recovery point for 25 hours.
resource "aws_cloudwatch_metric_alarm" "backup" {
  count               = var.backup_monitoring_enabled ? 1 : 0
  alarm_name          = local.alarm_names["backup-25h"]
  alarm_description   = local.alarm_descriptions["backup-25h"]
  namespace           = "Lighthouse/Backup"
  metric_name         = "SnapshotSucceeded"
  dimensions          = { Customer = var.customer_code }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 25
  datapoints_to_alarm = 25
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["backup-25h"]
  ok_actions          = local.alarm_actions["backup-25h"]
  tags                = local.common_tags
}

# Delivery failures on each priority topic. These actions go to the pipeline topic (email),
# not the priority topics, so they still arrive when the Lambda or SNS delivery is broken.
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
  tags                = local.common_tags
}
