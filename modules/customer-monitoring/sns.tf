# One topic per priority (alerts-p1/p2/p3) in the customer account. Every alarm publishes to
# the topic matching its priority; each topic delivers to the formatter Lambda in the
# management account. Only the alarm message crosses the account boundary.
#
# The pipeline topic is the exception: the SNS-failure alarm watches the priority topics'
# own delivery, so it must not depend on them (or on the Lambda) — it goes out by email.

locals {
  priorities = toset(["P1", "P2", "P3"])
}

# Topics are encrypted with a customer-managed key whose policy allows CloudWatch. The AWS
# managed key (alias/aws/sns) cannot be shared with CloudWatch, which makes the alarm
# action fail.
data "aws_iam_policy_document" "alerts_key" {
  statement {
    sid       = "EnableRootAccountAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarms"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowBudgetsAndCostAnomalyDetection"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description         = "Encrypts the ${var.environment} alert SNS topics"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alerts_key.json
  tags                = local.common_tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  for_each          = local.priorities
  name              = "${local.name_prefix}-alerts-${lower(each.key)}"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = merge(local.common_tags, { Priority = each.key })
}

data "aws_iam_policy_document" "alerts_topic" {
  for_each = local.priorities

  # Same-account publishers (CloudWatch alarms), as in SNS's default topic policy.
  statement {
    sid    = "AllowAccountPublish"
    effect = "Allow"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.alerts[each.key].arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowBudgetsAndCostAnomalyPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = var.management_account_id != null ? [1] : []
    content {
      sid       = "AllowManagementAccountSubscribe"
      effect    = "Allow"
      actions   = ["SNS:Subscribe", "SNS:Receive", "SNS:GetTopicAttributes", "SNS:ListSubscriptionsByTopic"]
      resources = [aws_sns_topic.alerts[each.key].arn]
      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${var.management_account_id}:root"]
      }
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  for_each = local.priorities
  arn      = aws_sns_topic.alerts[each.key].arn
  policy   = data.aws_iam_policy_document.alerts_topic[each.key].json
}

# Cross-account delivery: the topic owner subscribes the management account's Lambda. The
# Lambda's resource policy (modules/alert-formatter) permits invocation from this account.
resource "aws_sns_topic_subscription" "formatter" {
  for_each  = var.formatter_lambda_arn != null ? local.priorities : toset([])
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "lambda"
  endpoint  = var.formatter_lambda_arn
}

resource "aws_sns_topic" "pipeline" {
  name              = "${local.name_prefix}-alerts-pipeline"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "pipeline_email" {
  for_each  = toset(var.engineering_alert_emails)
  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = each.value
}
