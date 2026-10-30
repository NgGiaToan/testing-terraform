# Backup & DR Design Spec section 6 (S3 encryption) — customer-managed key backing the
# artifacts bucket and the AWS Backup vault, per Digi's Cryptography Standard. Rotation
# period and key policy shape are placeholders until that standard doc is linked in
# BACKUP-DR.md — revisit this policy once it is.

resource "aws_kms_key" "backup_dr" {
  description             = "Customer-managed key for Lighthouse backup/DR artifacts (S3 exports, AWS Backup vault)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.backup_dr_kms.json

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
  }
}

resource "aws_kms_alias" "backup_dr" {
  name          = "alias/lighthouse-backup-dr"
  target_key_id = aws_kms_key.backup_dr.key_id
}

data "aws_iam_policy_document" "backup_dr_kms" {
  statement {
    sid       = "EnableRootAccountAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # AWS Backup needs to create/manage grants on this key to encrypt vault recovery
  # points; the backup role needs to read/write objects it encrypts in the S3 bucket.
  statement {
    sid    = "AllowBackupServiceRoleUse"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.backup.arn]
    }
  }
}
