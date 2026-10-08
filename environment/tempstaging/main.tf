terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No `key` here on purpose: this is a per-PR ephemeral environment, so its state key
  # (tempstaging/pr-<number>/terraform.tfstate) is only known at workflow run time. It's
  # supplied via `terraform init -backend-config="key=..."` in infrastructure-pr.yml,
  # keyed off github.event.pull_request.number, so every PR gets its own isolated state
  # instead of racing on a shared one.
  backend "s3" {
    bucket         = "testing-terraform-tfstate"
    region         = "us-east-1"
    dynamodb_table = "testing-terraform-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "pr_number" {
  description = "PR number this TempStaging instance belongs to, used to tag resources for easy cleanup"
  type        = string
}

locals {
  environment = "tempstaging-pr${var.pr_number}"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-example-test-bucket-12345-${local.environment}"

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
    PRNumber    = var.pr_number
  }
}

resource "aws_security_group" "example" {
  name        = "example-sg-${local.environment}"
  description = "Example security group for testing scanners"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/24"]
  }

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
    PRNumber    = var.pr_number
  }
}
