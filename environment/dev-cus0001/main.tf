terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "dev-cus0001/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # Every resource of this customer carries the cost tags. The budget of modules/cost-monitoring
  # (environment/shr-monitoring) filters on the Instance tag, which is unique per customer and is not set here: its
  # value is the instance of this customer in cost_customers, and the tag has to be active in Billing.
  # CostCenter is not unique per customer, so it is only for grouping.
  default_tags {
    tags = {
      Customer    = local.customer_code
      Environment = local.environment
      CostCenter  = local.cost_center
      ManagedBy   = "terraform"
    }
  }
}

locals {
  environment   = "dev-cus0001"
  customer_code = "cus0001"
  cost_center   = "customer-${local.customer_code}"
}

resource "aws_s3_bucket" "example" {
  bucket = "my-example-test-bucket-12345-${local.environment}"

  tags = {
    Environment = local.environment
    Owner       = "platform-team"
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
  }
}
