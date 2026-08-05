plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.31.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"

  variable {
    format = "snake_case"
  }
  output {
    format = "snake_case"
  }
  resource {
    format = "snake_case"
  }
  data {
    format = "snake_case"
  }
  locals {
    format = "snake_case"
  }
}

rule "aws_resource_missing_tags" {
  enabled  = true
  severity = "error"
  tags = [
    "Environment",
    "Owner"
  ]
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}
