# Backup & DR Design Spec section 6 — bucket for anything exported out of the backup/DR
# flow: AWS Backup exports, Image Builder pipeline logs, DR drill evidence. Encrypted
# with the customer-managed key in kms.tf, not the default AWS-managed key.

resource "aws_s3_bucket" "backup_dr_artifacts" {
  bucket = "lighthouse-backup-dr-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
  }
}

resource "aws_s3_bucket_versioning" "backup_dr_artifacts" {
  bucket = aws_s3_bucket.backup_dr_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_dr_artifacts" {
  bucket = aws_s3_bucket.backup_dr_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup_dr.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup_dr_artifacts" {
  bucket                  = aws_s3_bucket.backup_dr_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
