# The Slack alert delivery Lambda, its management-account priority topics, and the pipeline topic.
#
# The priority topics below invoke the Lambda. Alarms of every customer account publish to them
# directly (one policy statement that takes alarms from any account, see aws_sns_topic_policy),
# and so do this account's own alarms, so there is no per-account setup on the Lambda. The pipeline
# topic carries the alarms that watch the Lambda itself, and it is wired to the same Lambda so they
# reach Slack (Engineering). Known limit: when the Lambda itself is down, those alarms (lambda-errors,
# lambda-throttles) cannot reach Slack through it, and are then visible only in CloudWatch.
# A path that does not depend on the Lambda is still to be added.

data "archive_file" "formatter" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/slack_formatter.py"
  output_path = "${path.module}/lambda_src/slack_formatter.zip"
}

# The webhook URL is a credential. Terraform creates only the empty secret; the value is set
# once with `aws secretsmanager put-secret-value` (see README), so it never enters the state.
# One secret per environment (and region: Secrets Manager is regional), read only by its Lambda,
# so what this Lambda posts can only reach this environment's channels. Which alarms reach this
# Lambda is decided by the topics they publish to, not by the secret.
# Skipped when slack_webhook_secret_arn points at a secret that already exists.
resource "aws_secretsmanager_secret" "slack_webhooks" {
  count       = var.slack_webhook_secret_arn == null ? 1 : 0
  name        = "${local.name_prefix}-slack-webhooks"
  description = "Slack Incoming Webhook URL(s) for ${var.environment} alerts in ${var.region}, used by the ${var.environment} alert delivery Lambda there. Value is set outside Terraform."
  tags        = local.tags
}

locals {
  slack_webhook_secret_arn = coalesce(var.slack_webhook_secret_arn, one(aws_secretsmanager_secret.slack_webhooks[*].arn))
}

resource "aws_cloudwatch_log_group" "formatter" {
  name              = "/aws/lambda/${local.name_prefix}-formatter"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_lambda_function" "formatter" {
  function_name    = "${local.name_prefix}-formatter"
  role             = aws_iam_role.formatter.arn
  handler          = "slack_formatter.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.formatter.output_path
  source_code_hash = data.archive_file.formatter.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      SLACK_WEBHOOK_SECRET_ARN = local.slack_webhook_secret_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.formatter, aws_iam_role_policy.formatter]
}

resource "aws_lambda_permission" "own_topics" {
  for_each      = local.priorities
  statement_id  = "AllowOwnAlerts-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.formatter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts[each.key].arn
}

# --- Management-account topics ---------------------------------------------------------
#
# The topics are encrypted at rest with the customer-managed key in kms.tf. Its policy takes
# CloudWatch alarms of any account, so a new customer still needs no change here.

resource "aws_sns_topic" "alerts" {
  for_each          = local.priorities
  name              = "${local.name_prefix}-alerts-${lower(each.key)}"
  kms_master_key_id = aws_kms_key.alerts.id
  tags              = merge(local.tags, { Priority = each.key })
}

# Who may publish to the topics: this account, and CloudWatch alarms of ANY AWS account as long
# as the alarm is named for the topic's priority. Alarm names are <customer>-<priority>-<key>, so
# the P1 topic takes *-P1-*, the P2 topic *-P2-*, and so on. Adding a customer needs no change here.
#
# The name rule is not a security boundary: anyone who knows a topic ARN can send alerts to Slack.
# A private webhook URL does not stop that, because messages enter through the topic.
data "aws_iam_policy_document" "alerts_topic" {
  for_each = local.priorities

  statement {
    # Only what the pipeline needs. The management actions of SNS's default policy
    # (SetTopicAttributes, AddPermission, RemovePermission, DeleteTopic) are left out on purpose:
    # whoever can change a topic's policy can reopen it to anyone. Terraform and admins manage
    # the topic through their IAM permissions, not through this policy.
    sid    = "AllowAccountOwner"
    effect = "Allow"
    actions = [
      "SNS:GetTopicAttributes",
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
    # Subscribing is allowed only for the alert delivery Lambda: no email, HTTP or other endpoint
    # can be added through this policy.
    sid       = "AllowSubscribeFormatterOnly"
    effect    = "Allow"
    actions   = ["SNS:Subscribe"]
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
    condition {
      test     = "StringEquals"
      variable = "sns:Protocol"
      values   = ["lambda"]
    }
    condition {
      test     = "StringEquals"
      variable = "sns:Endpoint"
      values   = [aws_lambda_function.formatter.arn]
    }
  }

  statement {
    sid       = "AllowAlarmsFromAnyAccount"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${var.region}:*:alarm:*-${each.key}-*"]
    }
  }

  # Cost alerts (modules/cost-monitoring) go to P3 (80% of a budget, a forecast, an anomaly) and P2 (100%), so only
  # those two topics take them, and only from this account.
  dynamic "statement" {
    for_each = each.key != "P1" ? [1] : []
    content {
      sid       = "AllowBudgetsOfThisAccount"
      effect    = "Allow"
      actions   = ["SNS:Publish"]
      resources = [aws_sns_topic.alerts[each.key].arn]
      principals {
        type        = "Service"
        identifiers = ["budgets.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:aws:budgets::${local.account_id}:*"]
      }
    }
  }

  # The AWS guide "Creating an Amazon SNS topic for anomaly notifications" documents this statement with the
  # aws:SourceAccount condition. If the first test anomaly alert still does not arrive, check the subscription first.
  dynamic "statement" {
    for_each = each.key != "P1" ? [1] : []
    content {
      sid       = "AllowCostAnomalyOfThisAccount"
      effect    = "Allow"
      actions   = ["SNS:Publish"]
      resources = [aws_sns_topic.alerts[each.key].arn]
      principals {
        type        = "Service"
        identifiers = ["costalerts.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  for_each = local.priorities
  arn      = aws_sns_topic.alerts[each.key].arn
  policy   = data.aws_iam_policy_document.alerts_topic[each.key].json
}

resource "aws_sns_topic_subscription" "alerts_formatter" {
  for_each  = local.priorities
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.formatter.arn
}

resource "aws_sns_topic" "pipeline" {
  name              = "${local.name_prefix}-pipeline"
  kms_master_key_id = aws_kms_key.alerts.id
  tags              = local.tags
}

# The pipeline topic delivers to the alert delivery Lambda too, so its alarms reach Slack. Only alarms of
# this account publish to it (the default topic policy), and their descriptions name the team
# (notify = Engineering), so the Lambda needs nothing else.
resource "aws_lambda_permission" "pipeline_topic" {
  statement_id  = "AllowOwnPipeline"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.formatter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.pipeline.arn
}

resource "aws_sns_topic_subscription" "pipeline_formatter" {
  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.formatter.arn

  depends_on = [aws_lambda_permission.pipeline_topic]
}
