terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

locals {
  name_prefix = "${var.environment}-canaries"
}

# Synthetics requires its own S3 bucket for run artifacts (screenshots, HAR files, logs) --
# one per customer, consistent with this repo's existing one-bucket-per-environment pattern.
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-artifacts-${var.customer_code}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "canary_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "canary" {
  name               = "${local.name_prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.canary_assume.json
  tags               = var.tags
}

# Standard Synthetics execution-role permissions per AWS's own canary IAM docs -- S3 write
# for artifacts, CloudWatch metrics scoped to the CloudWatchSynthetics namespace, and logs.
data "aws_iam_policy_document" "canary" {
  statement {
    sid       = "ArtifactsWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }

  statement {
    sid       = "ListAllBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/cwsyn-*"]
  }

  statement {
    sid       = "PutCanaryMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CloudWatchSynthetics"]
    }
  }
}

resource "aws_iam_role_policy" "canary" {
  name   = "${local.name_prefix}-execution"
  role   = aws_iam_role.canary.id
  policy = data.aws_iam_policy_document.canary.json
}

data "archive_file" "https_availability" {
  type        = "zip"
  source_dir  = "${path.module}/canary_src/https_availability"
  output_path = "${path.module}/canary_src/https_availability.zip"
}

resource "aws_synthetics_canary" "https_availability" {
  name                 = "${var.customer_code}-https-availability"
  artifact_s3_location = "s3://${aws_s3_bucket.artifacts.bucket}/https-availability"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "https_availability.handler"
  runtime_version      = var.runtime_version
  zip_file             = data.archive_file.https_availability.output_path
  start_canary         = true
  tags                 = var.tags

  schedule {
    expression = var.https_availability_schedule_expression
  }

  run_config {
    timeout_in_seconds = 30
    environment_variables = {
      TARGET_URL = var.target_url
    }
  }
}

data "archive_file" "workflow" {
  type        = "zip"
  source_dir  = "${path.module}/canary_src/workflow"
  output_path = "${path.module}/canary_src/workflow.zip"
}

resource "aws_synthetics_canary" "workflow" {
  name                 = "${var.customer_code}-workflow"
  artifact_s3_location = "s3://${aws_s3_bucket.artifacts.bucket}/workflow"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "workflow.handler"
  runtime_version      = var.runtime_version
  zip_file             = data.archive_file.workflow.output_path
  start_canary         = true
  tags                 = var.tags

  schedule {
    expression = var.workflow_schedule_expression
  }

  run_config {
    timeout_in_seconds = 60
    environment_variables = {
      TARGET_URL = var.target_url
    }
  }
}
