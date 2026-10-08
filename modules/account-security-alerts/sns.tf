resource "aws_sns_topic" "security_alerts" {
  name = local.name_prefix
}

# EventBridge rules (eventbridge.tf) publish directly to this topic, which requires an
# explicit resource policy grant, same as Budgets/Cost Anomaly Detection in
# modules/customer-monitoring.
data "aws_iam_policy_document" "security_alerts_publish" {
  statement {
    sid     = "AllowEventBridgePublish"
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.security_alerts.arn]
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.security_alerts_publish.json
}
