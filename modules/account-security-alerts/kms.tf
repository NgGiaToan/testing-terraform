# The customer-managed key that encrypts the security_alerts topic at rest.
#
# An AWS service can publish to an encrypted topic only if the key is customer-managed and its
# policy lets that service use it.
# https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html
#
# Only EventBridge (eventbridge.tf) publishes to the topic: the AWS docs say aws:SourceAccount,
# aws:SourceArn and aws:SourceOrgID are NOT supported in the key policy for
# EventBridge-to-encrypted-topic, so that statement has no condition.
#
# Not verified: that the Lambda subscriber (slack-lambda.tf) needs no permission on the key. Test with
# a real event and a real alarm after applying.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "security_alerts_key" {
  statement {
    # Without this statement nobody can manage the key (or grant access to it through IAM).
    sid       = "EnableIamPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowEventBridge"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"] # in a key policy, "*" is this key
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "security_alerts" {
  description             = "Encrypts the ${local.name_prefix} topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.security_alerts_key.json
}

resource "aws_kms_alias" "security_alerts" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.security_alerts.key_id
}
