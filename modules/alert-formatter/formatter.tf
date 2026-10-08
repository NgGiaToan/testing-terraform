# The Slack formatter Lambda, its management-account priority topics, and the pipeline topic.
#
# Customer accounts' priority topics invoke the Lambda directly (cross-account SNS → Lambda in
# the same region). This account's own alarms use the priority topics below, which invoke the
# same Lambda. The pipeline topic is deliberately NOT wired to the Lambda: it carries the
# alarms that watch the Lambda, so it delivers by email.

data "archive_file" "formatter" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/slack_formatter.py"
  output_path = "${path.module}/lambda_src/slack_formatter.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "formatter" {
  name               = "${local.name_prefix}-formatter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "formatter" {
  statement {
    sid       = "ReadSlackToken"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.slack_bot_token_secret_arn]
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.formatter.arn}:*"]
  }
}

resource "aws_iam_role_policy" "formatter" {
  name   = "${local.name_prefix}-formatter"
  role   = aws_iam_role.formatter.id
  policy = data.aws_iam_policy_document.formatter.json
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
      SLACK_TOKEN_SECRET_ARN    = var.slack_bot_token_secret_arn
      SLACK_CHANNEL_OPERATIONS  = var.slack_channel_operations
      SLACK_CHANNEL_ENGINEERING = var.slack_channel_engineering
    }
  }

  depends_on = [aws_cloudwatch_log_group.formatter, aws_iam_role_policy.formatter]
}

# Resource policy: one statement per customer account, limited to that account's alert
# topics (<environment>-monitoring-alerts-p1/p2/p3).
resource "aws_lambda_permission" "customer_topics" {
  for_each       = toset(var.customer_account_ids)
  statement_id   = "AllowCustomerAlerts-${each.value}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.formatter.function_name
  principal      = "sns.amazonaws.com"
  source_account = each.value
  source_arn     = "arn:aws:sns:${var.region}:${each.value}:*-monitoring-alerts-p*"
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

  # A topic encrypted with the AWS managed key makes the alarm action fail; CloudWatch needs
  # to be able to use the key.
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
}

resource "aws_kms_key" "alerts" {
  description         = "Encrypts the management-account alert SNS topics"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alerts_key.json
  tags                = local.tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  for_each          = local.priorities
  name              = "${local.name_prefix}-alerts-${lower(each.key)}"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = merge(local.tags, { Priority = each.key })
}

resource "aws_sns_topic_subscription" "alerts_formatter" {
  for_each  = local.priorities
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.formatter.arn
}

resource "aws_sns_topic" "pipeline" {
  name              = "${local.name_prefix}-pipeline"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = local.tags
}

resource "aws_sns_topic_subscription" "pipeline_email" {
  for_each  = toset(var.engineering_alert_emails)
  topic_arn = aws_sns_topic.pipeline.arn
  protocol  = "email"
  endpoint  = each.value
}
