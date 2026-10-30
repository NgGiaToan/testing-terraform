data "archive_file" "security_notifier" {
  count       = local.slack_enabled ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda_src/security_notifier.py"
  output_path = "${path.module}/lambda_src/security_notifier.zip"
}

data "aws_iam_policy_document" "security_lambda_assume" {
  count = local.slack_enabled ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "security_lambda" {
  count              = local.slack_enabled ? 1 : 0
  name               = "${local.name_prefix}-notifier"
  assume_role_policy = data.aws_iam_policy_document.security_lambda_assume[0].json
}

data "aws_iam_policy_document" "security_lambda" {
  count = local.slack_enabled ? 1 : 0

  statement {
    sid       = "ReadSlackToken"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.slack_bot_token_secret_arn]
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-notifier:*"]
  }
}

resource "aws_iam_role_policy" "security_lambda" {
  count  = local.slack_enabled ? 1 : 0
  name   = "${local.name_prefix}-notifier"
  role   = aws_iam_role.security_lambda[0].id
  policy = data.aws_iam_policy_document.security_lambda[0].json
}

resource "aws_lambda_function" "security_notifier" {
  count            = local.slack_enabled ? 1 : 0
  function_name    = "${local.name_prefix}-notifier"
  role             = aws_iam_role.security_lambda[0].arn
  handler          = "security_notifier.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.security_notifier[0].output_path
  source_code_hash = data.archive_file.security_notifier[0].output_base64sha256

  environment {
    variables = {
      SLACK_TOKEN_SECRET_ARN = var.slack_bot_token_secret_arn
      SLACK_CHANNEL          = coalesce(var.slack_channel, "")
    }
  }
}

resource "aws_lambda_permission" "security_alerts" {
  count         = local.slack_enabled ? 1 : 0
  statement_id  = "AllowSecurityAlertsSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_alerts.arn
}

resource "aws_sns_topic_subscription" "security_alerts_lambda" {
  count     = local.slack_enabled ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.security_notifier[0].arn
}
