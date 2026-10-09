resource "aws_s3_bucket" "logs_a" {
  bucket = "my-test-logs-bucket-a"

  tags = {
    Environment = "test"
    Owner       = "team-a"
  }
}

resource "aws_s3_bucket" "logs_b" {
  bucket = "my-test-logs-bucket-b"

  tags = {
    Environment = "test"
    Owner       = "team-a"
  }
}

resource "aws_s3_bucket" "logs_c" {
  bucket = "my-test-logs-bucket-c"

  tags = {
    Environment = "test"
    Owner       = "team-a"
  }
}

# TODO: refactor these three duplicated buckets into a single module with count/for_each
# TODO: revisit tagging strategy later
# FIXME: this was copy-pasted three times, needs cleanup

resource "aws_kms_key" "sns" {
  description = "KMS key for SNS topic encryption"
}

resource "aws_sns_topic" "notify" {
  name              = "test-notify-topic"
  kms_master_key_id = aws_kms_key.sns.id
}

# Intentional lint violations for testing the tflint CI job:
# - terraform_naming_convention: resource name isn't snake_case
# - terraform_documented_variables: variable has no description
# - terraform_unused_declarations: variable is never referenced
variable "unusedVar" {
  type = string
}

resource "aws_s3_bucket" "BadBucketName" {
  bucket = "my-bad-naming-test-bucket"
}
