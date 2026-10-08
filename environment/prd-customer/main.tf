terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No `key` here on purpose: this single module is applied once per customer, so its
  # state key (oglh/customers/<code>/terraform.tfstate) is only known at workflow run
  # time. It's supplied via `terraform init -backend-config="key=..."`, keyed off the
  # customer code discovered from SSM Parameter Store (/oglh/customers/<code>) — customers
  # are data (who they are can change without a code change), not directories in this repo.
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

variable "customer_code" {
  description = "Customer code, e.g. \"cus001\" — read from an SSM parameter under /oglh/customers/<code>"
  type        = string
}

locals {
  environment = "prod-${var.customer_code}"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-example-test-bucket-12345-${local.environment}"

  tags = {
    Environment  = local.environment
    Owner        = "platform-team"
    CustomerCode = var.customer_code
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
    Environment  = local.environment
    Owner        = "platform-team"
    CustomerCode = var.customer_code
  }
}
