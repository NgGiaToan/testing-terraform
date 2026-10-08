terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Customer    = var.customer_code
    Environment = var.environment
    Product     = var.product
    CostCenter  = var.cost_center
    Region      = var.region
    ManagedBy   = "terraform"
  }

  name_prefix      = "${var.environment}-monitoring"
  account_id       = data.aws_caller_identity.current.account_id
  instance_enabled = var.instance_id != null
  alb_enabled      = var.alb_arn_suffix != null
  nlb_enabled      = var.nlb_arn_suffix != null
}
