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

# The webhook URL is a credential. Terraform creates only the empty secret; the value is set
# once with `aws secretsmanager put-secret-value` (see README), so it never enters the state.
# Skipped when slack_webhook_secret_arn points at a secret that already exists.
resource "aws_secretsmanager_secret" "slack_webhooks" {
  count       = var.slack_webhook_secret_arn == null ? 1 : 0
  name        = "${local.name_prefix}-slack-webhooks"
  description = "Slack Incoming Webhook URL(s) for the alert formatter Lambda. Value is set outside Terraform."
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

locals {
  # Regions of customer topics that may invoke the Lambda: its own region plus var.customer_regions.
  customer_topic_regions = distinct(concat([var.region], var.customer_regions))

  # Regions that need an explicit opt-in (launched after 2019-03-20). SNS in one of these
  # invokes a Lambda in another region as sns.<region>.amazonaws.com, not sns.amazonaws.com.
  # https://docs.aws.amazon.com/sns/latest/dg/sns-cross-region-delivery.html
  opt_in_regions = [
    "af-south-1", "ap-east-1", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "eu-south-1",
    "eu-south-2", "eu-central-2", "il-central-1", "me-south-1", "me-central-1",
  ]

  customer_topic_grants = {
    for pair in setproduct(var.customer_account_ids, local.customer_topic_regions) :
    "${pair[0]}-${pair[1]}" => { account = pair[0], region = pair[1] }
  }
}

# Resource policy: one statement per customer account and region, limited to that account's
# alert topics (<environment>-monitoring-alerts-p1/p2/p3) in that region.
resource "aws_lambda_permission" "customer_topics" {
  for_each       = local.customer_topic_grants
  statement_id   = "AllowCustomerAlerts-${each.value.account}-${each.value.region}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.formatter.function_name
  principal      = contains(local.opt_in_regions, each.value.region) ? "sns.${each.value.region}.amazonaws.com" : "sns.amazonaws.com"
  source_account = each.value.account
  source_arn     = "arn:aws:sns:${each.value.region}:${each.value.account}:*-monitoring-alerts-p*"
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
