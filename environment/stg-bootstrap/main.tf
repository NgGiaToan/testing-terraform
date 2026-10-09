terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "testing-terraform-tfstate"
    key            = "stg-bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "testing-terraform-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  environment = "stg-bootstrap"
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
