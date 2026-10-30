# Backup & DR Design Spec section 1 — daily AMI snapshot, 30-day retention, selected by
# tag rather than instance ID so new instances are picked up automatically.
#
# Selection uses a dedicated `Backup = "true"` tag rather than enumerating each
# environment's `Environment` value: enumerating would mean editing this module every
# time a new customer environment is added, which defeats the "automatic" requirement.
# Once EC2 instances exist in environment/*-customer and environment/*-admin, tag them
# `Backup = "true"` to bring them under this plan.

resource "aws_backup_vault" "lighthouse" {
  name        = "lighthouse-backup-vault"
  kms_key_arn = aws_kms_key.backup_dr.arn

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
  }
}

resource "aws_backup_plan" "lighthouse_daily" {
  name = "lighthouse-daily-ami-snapshot"

  rule {
    rule_name         = "daily-05-00-utc"
    target_vault_name = aws_backup_vault.lighthouse.name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = 30
    }
  }

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
  }
}

resource "aws_backup_selection" "lighthouse_tagged" {
  name         = "lighthouse-tagged-instances"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.lighthouse_daily.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
