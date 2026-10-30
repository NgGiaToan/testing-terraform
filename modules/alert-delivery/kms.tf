# The customer-managed key that encrypts this deployment's topics (alerts P1-P3, pipeline) at rest.
#
# Why a customer-managed key: an AWS service can publish to an encrypted topic only if the key is
# customer-managed and its policy lets that service use it (the AWS-managed alias/aws/sns key
# cannot be edited, so CloudWatch could not use it).
# https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html
#
# Who may use it:
#   - this account (the root statement), so IAM policies can grant access, such as the admins who apply
#     this module;
#   - CloudWatch alarms of ANY account, in this region: the topic policy (formatter.tf) already
#     takes alarms from any account, and a customer account's alarm needs the key to publish to an
#     encrypted topic. The statement names the service, not each account, so adding a customer
#     needs no change here. The topic policy still decides which alarms are accepted by name.
#
# Not verified: the AWS docs show this statement for a single account's alarms. Allowing the
# alarms of any account (the `*` account in aws:SourceArn) is this module's own design. Test with
# a real alarm in a customer account after applying: a key policy that is too narrow stops that
# account's alerts without an error anywhere but the alarm's history.

data "aws_iam_policy_document" "alerts_key" {
  statement {
    # Without this statement nobody can manage the key (or grant access to it through IAM).
    sid       = "EnableIamPermissions"
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
    resources = ["*"] # in a key policy, "*" is this key
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${var.region}:*:alarm:*"]
    }
  }

  # AWS Budgets and Cost Anomaly Detection (modules/cost-monitoring) publish to the same topics, so they need the
  # key too, from this account only. AWS documents the key statement for Cost Anomaly Detection with aws:SourceAccount.
  # The text of the key statement for Budgets is not verified (the Budgets guide shows it in a tab that could not be
  # read): if a budget cannot publish to the encrypted topic, copy the statement from that guide.
  statement {
    sid       = "AllowCostAlertsOfThisAccount"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"] # in a key policy, "*" is this key
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "Encrypts the ${local.name_prefix} alert topics"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.alerts_key.json
  tags                    = local.tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}
