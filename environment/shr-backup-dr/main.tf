terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Shared, account-level backup/DR infrastructure (KMS, S3, AWS Backup, IAM) for all
  # Lighthouse customer + admin environments. Same convention as shr-iam/shr-bootstrap:
  # account-level, rarely changes, applied manually by an admin — not from CI.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-backup-dr/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  environment = "shr-backup-dr"
}
