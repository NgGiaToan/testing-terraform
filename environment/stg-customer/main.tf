terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No `key` here on purpose: this single module is applied once per Demo/Testing env, so
  # its state key (envs/<name>/terraform.tfstate) is only known at workflow run time. It's
  # supplied via `terraform init -backend-config="key=..."`, keyed off the env name
  # discovered from SSM Parameter Store (/envs/stg_*) — these envs are data, not
  # directories in this repo.
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

variable "env_name" {
  description = "Demo/Testing env name, e.g. \"stg_qa\" — read from an SSM parameter under /envs/stg_*"
  type        = string
}

locals {
  environment = "staging-${var.env_name}"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-example-test-bucket-12345-${local.environment}"

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
    EnvName     = var.env_name
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
    EnvName     = var.env_name
  }
}
