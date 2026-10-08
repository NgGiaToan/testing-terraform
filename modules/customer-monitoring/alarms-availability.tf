# Availability & health checks, remote access, web protection and certificates. Name, SNS
# topic and description come from local.alerts (alerts.tf). "N of M" in the spec maps to
# datapoints_to_alarm / evaluation_periods.

resource "aws_cloudwatch_metric_alarm" "status_check" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["status-check"]
  alarm_description   = local.alarm_descriptions["status-check"]
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions["status-check"]
  ok_actions          = local.alarm_actions["status-check"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "https_canary" {
  count               = var.https_availability_canary_name != null ? 1 : 0
  alarm_name          = local.alarm_names["https-canary"]
  alarm_description   = local.alarm_descriptions["https-canary"]
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  dimensions          = { CanaryName = var.https_availability_canary_name }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 100
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["https-canary"]
  ok_actions          = local.alarm_actions["https-canary"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_healthy" {
  count               = local.alb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["alb-healthy"]
  alarm_description   = local.alarm_descriptions["alb-healthy"]
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["alb-healthy"]
  ok_actions          = local.alarm_actions["alb-healthy"]
  tags                = local.common_tags
}

# (Target 5xx + ELB 5xx) / requests x 100. Evaluated only when the minute had at least
# alb_5xx_min_requests_per_minute requests, so errors on near-idle traffic don't alarm.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = local.alb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["alb-5xx"]
  alarm_description   = local.alarm_descriptions["alb-5xx"]
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = var.alb_5xx_rate_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["alb-5xx"]
  ok_actions          = local.alarm_actions["alb-5xx"]
  tags                = local.common_tags

  metric_query {
    id          = "rate"
    expression  = "IF(requests >= ${var.alb_5xx_min_requests_per_minute}, (target5xx + elb5xx) / requests * 100, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "target5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "elb5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "workflow_canary" {
  count               = var.synthetics_canary_name != null ? 1 : 0
  alarm_name          = local.alarm_names["workflow-canary"]
  alarm_description   = local.alarm_descriptions["workflow-canary"]
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  dimensions          = { CanaryName = var.synthetics_canary_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 100
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["workflow-canary"]
  ok_actions          = local.alarm_actions["workflow-canary"]
  tags                = local.common_tags
}

# Only published for Nitro instances.
resource "aws_cloudwatch_metric_alarm" "ebs_status" {
  count               = local.instance_enabled ? 1 : 0
  alarm_name          = local.alarm_names["ebs-status"]
  alarm_description   = local.alarm_descriptions["ebs-status"]
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_AttachedEBS"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions["ebs-status"]
  ok_actions          = local.alarm_actions["ebs-status"]
  tags                = local.common_tags
}

# --- Remote access (OpenVPN via NLB) ---------------------------------------------------

# Maximum, not Average: a node without a target in its own zone (NLB cross-zone is off by
# default) reports 0 and would otherwise hide the unhealthy host.
resource "aws_cloudwatch_metric_alarm" "vpn_healthy" {
  count               = local.nlb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["vpn-healthy"]
  alarm_description   = local.alarm_descriptions["vpn-healthy"]
  namespace           = "AWS/NetworkELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.nlb_arn_suffix, TargetGroup = var.nlb_target_group_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["vpn-healthy"]
  ok_actions          = local.alarm_actions["vpn-healthy"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "vpn_connections" {
  count               = local.nlb_enabled ? 1 : 0
  alarm_name          = local.alarm_names["vpn-connections"]
  alarm_description   = local.alarm_descriptions["vpn-connections"]
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold_metric_id = "band"
  comparison_operator = "LessThanLowerThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["vpn-connections"]
  ok_actions          = local.alarm_actions["vpn-connections"]
  tags                = local.common_tags

  metric_query {
    id          = "flows"
    return_data = true
    metric {
      namespace   = "AWS/NetworkELB"
      metric_name = "ActiveFlowCount"
      dimensions  = { LoadBalancer = var.nlb_arn_suffix, TargetGroup = var.nlb_target_group_arn_suffix }
      stat        = "Average"
      period      = 300
    }
  }

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(flows, ${var.anomaly_band_width})"
    label       = "ActiveFlowCount (expected range)"
    return_data = true
  }
}

# --- Web protection & certificates -----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  count               = var.waf_web_acl_name != null ? 1 : 0
  alarm_name          = local.alarm_names["waf-blocked"]
  alarm_description   = local.alarm_descriptions["waf-blocked"]
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold_metric_id = "band"
  comparison_operator = "GreaterThanUpperThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions["waf-blocked"]
  ok_actions          = local.alarm_actions["waf-blocked"]
  tags                = local.common_tags

  metric_query {
    id          = "blocked"
    return_data = true
    metric {
      namespace   = "AWS/WAFV2"
      metric_name = "BlockedRequests"
      dimensions = {
        WebACL = var.waf_web_acl_name
        Rule   = "ALL"
        Region = coalesce(var.waf_web_acl_region, var.region)
      }
      stat   = "Sum"
      period = 300
    }
  }

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(blocked, ${var.anomaly_band_width})"
    label       = "BlockedRequests (expected range)"
    return_data = true
  }
}

# DaysToExpiry is published once a day. ACM renews DNS-validated certificates automatically
# 45 days out, so either alarm firing means renewal is failing. Missing data breaches: a
# certificate that stops reporting should not look healthy.
resource "aws_cloudwatch_metric_alarm" "cert_warning" {
  count               = var.acm_certificate_arn != null ? 1 : 0
  alarm_name          = local.alarm_names["cert-warning"]
  alarm_description   = local.alarm_descriptions["cert-warning"]
  namespace           = "AWS/CertificateManager"
  metric_name         = "DaysToExpiry"
  dimensions          = { CertificateArn = var.acm_certificate_arn }
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.acm_warning_days
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["cert-warning"]
  ok_actions          = local.alarm_actions["cert-warning"]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cert_critical" {
  count               = var.acm_certificate_arn != null ? 1 : 0
  alarm_name          = local.alarm_names["cert-critical"]
  alarm_description   = local.alarm_descriptions["cert-critical"]
  namespace           = "AWS/CertificateManager"
  metric_name         = "DaysToExpiry"
  dimensions          = { CertificateArn = var.acm_certificate_arn }
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.acm_critical_days
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions["cert-critical"]
  ok_actions          = local.alarm_actions["cert-critical"]
  tags                = local.common_tags
}
