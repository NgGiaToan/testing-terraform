# IAM role of the alert delivery Lambda: who may assume it, and what it may do.
#
# The trust policy below is for the formatter Lambda's role.
# Who may *invoke* the Lambda (the customers' SNS topics) is a resource policy, not part of
# this role: see aws_lambda_permission in formatter.tf.

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
  name               = "${local.name_prefix}-formatter" # name_prefix has the region: IAM is global
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

# Read this environment's Slack webhook secret and write its own logs, nothing else.
data "aws_iam_policy_document" "formatter" {
  statement {
    sid       = "ReadSlackWebhooks"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.slack_webhook_secret_arn]
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
