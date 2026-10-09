# GuardDuty: split High (>= threshold) vs Medium so the Lambda can label severity without
# re-deriving it from the raw finding. EventBridge's "numeric" matcher supports >=, so no
# custom Lambda logic is needed just to bucket severity.
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name = "${local.name_prefix}-guardduty-high"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", var.guardduty_high_severity_threshold] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high" {
  rule = aws_cloudwatch_event_rule.guardduty_high.name
  arn  = aws_sns_topic.security_alerts.arn
}

resource "aws_cloudwatch_event_rule" "guardduty_medium" {
  name = "${local.name_prefix}-guardduty-medium"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{
        numeric = [">=", var.guardduty_medium_severity_threshold, "<", var.guardduty_high_severity_threshold]
      }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_medium" {
  rule = aws_cloudwatch_event_rule.guardduty_medium.name
  arn  = aws_sns_topic.security_alerts.arn
}

# Security Hub re-sends every update to an existing finding, not just new ones — scoped to
# Workflow.Status = NEW so a control being re-scanned doesn't re-fire the alert each time.
resource "aws_cloudwatch_event_rule" "security_hub" {
  count = var.enable_security_hub_alerts ? 1 : 0
  name  = "${local.name_prefix}-security-hub-new-findings"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Workflow = { Status = ["NEW"] }
        Severity = { Label = ["CRITICAL", "HIGH"] }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "security_hub" {
  count = var.enable_security_hub_alerts ? 1 : 0
  rule  = aws_cloudwatch_event_rule.security_hub[0].name
  arn   = aws_sns_topic.security_alerts.arn
}

resource "aws_cloudwatch_event_rule" "access_analyzer" {
  count = var.enable_access_analyzer_alerts ? 1 : 0
  name  = "${local.name_prefix}-access-analyzer"
  event_pattern = jsonencode({
    source      = ["aws.access-analyzer"]
    detail-type = ["Access Analyzer Finding"]
  })
}

resource "aws_cloudwatch_event_target" "access_analyzer" {
  count = var.enable_access_analyzer_alerts ? 1 : 0
  rule  = aws_cloudwatch_event_rule.access_analyzer[0].name
  arn   = aws_sns_topic.security_alerts.arn
}
