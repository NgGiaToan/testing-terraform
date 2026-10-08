# The alert catalogue: one entry per alert key from the monitoring spec. Every alarm in
# alarms-*.tf takes its name, SNS topic and JSON description from here, so the priority,
# the audience and the wording of the trigger live in exactly one place. The `condition`
# text is built from the same variables as the alarm itself, so it cannot drift from it.
#
# Alarm name:        <customer>-<priority>-<alert-key>   e.g. acme-P1-https-canary
# Alarm description: JSON read by the formatter Lambda (modules/alert-formatter) —
#                    priority, customer, alert_type, service, condition, dashboard_url, and
#                    `notify` (the teams that receive it: Operations and/or Engineering).

locals {
  alerts = {
    # --- Availability & health ---------------------------------------------------------
    "status-check" = {
      priority  = "P1", notify = ["Operations"], service = "EC2", alert_type = "StatusCheckFailed"
      condition = "EC2 status check failed for 3 consecutive minutes"
    }
    "https-canary" = {
      priority  = "P1", notify = ["Operations"], service = "Synthetics", alert_type = "HTTPS canary"
      condition = "HTTPS canary against the customer domain (port 443, expects HTTP 200) failed for 3 consecutive minutes"
    }
    "alb-healthy" = {
      priority  = "P1", notify = ["Operations"], service = "ALB", alert_type = "UnHealthyHostCount"
      condition = "ALB has at least one unhealthy target for 3 consecutive minutes"
    }
    "alb-5xx" = {
      priority  = "P2", notify = ["Operations"], service = "ALB", alert_type = "5xx error rate"
      condition = "ALB 5xx (target + load balancer) above ${var.alb_5xx_rate_threshold_percent}% of requests for 5 consecutive minutes, with at least ${var.alb_5xx_min_requests_per_minute} requests a minute"
    }
    "workflow-canary" = {
      priority  = "P2", notify = ["Operations"], service = "Synthetics", alert_type = "Workflow canary"
      condition = "Workflow canary failed 2 consecutive runs (10 minutes)"
    }
    "ebs-status" = {
      priority  = "P2", notify = ["Operations"], service = "EBS", alert_type = "StatusCheckFailed_AttachedEBS"
      condition = "Attached EBS volume status check failed for 3 consecutive minutes"
    }

    # --- Performance & capacity --------------------------------------------------------
    "cpu-warning" = {
      priority  = "P3", notify = ["Operations"], service = "EC2", alert_type = "CPUUtilization"
      condition = "CPU above ${var.cpu_warning_threshold}% for 15 consecutive minutes"
    }
    "cpu-critical" = {
      priority  = "P2", notify = ["Operations"], service = "EC2", alert_type = "CPUUtilization"
      condition = "CPU above ${var.cpu_critical_threshold}% for 10 consecutive minutes"
    }
    "memory-warning" = {
      priority  = "P3", notify = ["Operations"], service = "CWAgent", alert_type = "mem_used_percent"
      condition = "Memory used above ${var.memory_warning_threshold}% for 15 consecutive minutes"
    }
    "memory-critical" = {
      priority  = "P2", notify = ["Operations"], service = "CWAgent", alert_type = "mem_used_percent"
      condition = "Memory used above ${var.memory_critical_threshold}% for 10 consecutive minutes"
    }
    "disk-warning" = {
      priority  = "P3", notify = ["Operations"], service = "CWAgent", alert_type = "disk_used_percent"
      condition = "Disk used above ${var.disk_warning_threshold}% for 15 minutes (3 x 5 min)"
    }
    "disk-critical" = {
      priority  = "P2", notify = ["Operations"], service = "CWAgent", alert_type = "disk_used_percent"
      condition = "Disk used above ${var.disk_critical_threshold}% for 15 minutes (3 x 5 min)"
    }
    "alb-latency" = {
      priority  = "P2", notify = ["Operations"], service = "ALB", alert_type = "TargetResponseTime"
      condition = "ALB p95 response time above ${var.alb_latency_p95_threshold_seconds}s for 10 consecutive minutes"
    }
    "alb-request-rate" = {
      priority  = "P3", notify = ["Operations"], service = "ALB", alert_type = "RequestCount"
      condition = "ALB request rate above its expected range (anomaly band width ${var.anomaly_band_width}) for 10 consecutive minutes"
    }
    "network-egress" = {
      priority  = "P3", notify = ["Operations"], service = "EC2", alert_type = "NetworkOut"
      condition = "Outbound network traffic above its expected range (anomaly band width ${var.anomaly_band_width}) for 30 minutes"
    }
    "agent-heartbeat" = {
      priority  = "P2", notify = ["Engineering"], service = "CWAgent", alert_type = "Monitoring agent heartbeat"
      condition = "CloudWatch agent sent no memory samples for 10 minutes — memory and disk alarms are blind"
    }

    # --- Remote access (OpenVPN via NLB) -----------------------------------------------
    "vpn-healthy" = {
      priority  = "P1", notify = ["Operations"], service = "NLB", alert_type = "UnHealthyHostCount"
      condition = "OpenVPN target unhealthy for 3 consecutive minutes — VPN connections impossible"
    }
    "vpn-connections" = {
      priority  = "P2", notify = ["Operations"], service = "NLB", alert_type = "ActiveFlowCount"
      condition = "Active VPN flows below their expected range (anomaly band width ${var.anomaly_band_width}) for 15 minutes"
    }

    # --- Web protection & certificates -------------------------------------------------
    "waf-blocked" = {
      priority  = "P3", notify = ["Operations"], service = "WAF", alert_type = "BlockedRequests"
      condition = "WAF blocked requests above their expected range (anomaly band width ${var.anomaly_band_width}) for 10 minutes"
    }
    "cert-warning" = {
      priority  = "P2", notify = ["Operations"], service = "ACM", alert_type = "DaysToExpiry"
      condition = "Certificate expires in fewer than ${var.acm_warning_days} days"
    }
    "cert-critical" = {
      priority  = "P1", notify = ["Operations"], service = "ACM", alert_type = "DaysToExpiry"
      condition = "Certificate expires in fewer than ${var.acm_critical_days} days"
    }

    # --- Platform health ---------------------------------------------------------------
    "backup-25h" = {
      priority  = "P1", notify = ["Engineering"], service = "Backup", alert_type = "SnapshotSucceeded"
      condition = "No successful daily AMI snapshot for 25 hours"
    }
    "sns-failures" = {
      priority  = "P2", notify = ["Engineering"], service = "SNS", alert_type = "NumberOfNotificationsFailed"
      condition = "SNS could not deliver an alert notification to the formatter Lambda"
    }
  }

  alarm_names = {
    for key, a in local.alerts : key => "${var.customer_code}-${a.priority}-${key}"
  }

  alarm_descriptions = {
    for key, a in local.alerts : key => jsonencode({
      priority      = a.priority
      customer      = var.customer_code
      alert_type    = a.alert_type
      service       = a.service
      condition     = a.condition
      dashboard_url = coalesce(var.dashboard_url, "")
      notify        = a.notify
    })
  }

  # alarm_actions and ok_actions publish to the priority topic in this account and region.
  alarm_actions = {
    for key, a in local.alerts : key => [aws_sns_topic.alerts[a.priority].arn]
  }
}
