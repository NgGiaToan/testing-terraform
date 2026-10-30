terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uses the remote backend (unlike shr-bootstrap) since by the time this is applied,
  # shr-bootstrap has already created the bucket this state lives in. Still applied
  # manually by an admin, not from CI — same reasoning as shr-bootstrap: this is
  # account-level and rarely changes. Locking is S3 native (use_lockfile) — no DynamoDB
  # table in this repo anymore.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-iam/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Looked up rather than referenced across states — shr-bootstrap's bucket lives in its
# own state file, not this one.
data "aws_s3_bucket" "tfstate" {
  bucket = "testing-terraform-tfstate"
}

# Used to scope the monitoring-module ARNs in github_actions.tf to this account rather
# than "*".
data "aws_caller_identity" "current" {}
