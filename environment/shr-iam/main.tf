terraform {
  required_version = ">= 1.5.0"

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
  # shr-bootstrap has already created the bucket/table this state lives in. Still
  # applied manually by an admin, not from CI — same reasoning as shr-bootstrap: this is
  # account-level and rarely changes.
  backend "s3" {
    bucket         = "testing-terraform-tfstate"
    key            = "shr-iam/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "testing-terraform-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# Looked up rather than referenced across states — shr-bootstrap's bucket/table live in
# their own state file, not this one.
data "aws_s3_bucket" "tfstate" {
  bucket = "testing-terraform-tfstate"
}

data "aws_dynamodb_table" "tflock" {
  name = "testing-terraform-tflock"
}
