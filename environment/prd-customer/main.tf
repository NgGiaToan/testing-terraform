terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No `key` here on purpose: this single module is applied once per customer, so its
  # state key (oglh/customers/<code>/terraform.tfstate) is only known at workflow run
  # time. It's supplied via `terraform init -backend-config="key=..."`, keyed off the
  # customer code discovered from Secrets Manager (one secret per customer, named
  # oglh/customers/<code>) — customers are data (who they are can change without a code
  # change), not directories in this repo.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # Every resource of this customer carries the cost tags (see dev-cus0001/main.tf). The budget filters on the
  # Instance tag of this customer (instance in cost_customers, environment/shr-monitoring), not on CostCenter.
  default_tags {
    tags = {
      Customer    = var.customer_code
      Environment = local.environment
      CostCenter  = local.cost_center
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment = "prod-${var.customer_code}"
  cost_center = "customer-${var.customer_code}"
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
