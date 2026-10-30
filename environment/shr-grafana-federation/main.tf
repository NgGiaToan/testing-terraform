# Grafana (on an Azure VM) reads AWS CloudWatch with no access key: OIDC federation. See README.md.
#
# Account-level IAM, applied once by an admin like shr-iam and shr-backup-dr: not from CI, and not one per
# environment or region (IAM is global), so there is NO workspace here: one deployment, one state.
#
# NOT validated: written against the provider's documentation. Run `terraform init`, `terraform validate` and read
# the plan before the first apply.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.81" # 5.81 or later: AWS fetches the signing keys of the OIDC issuer itself (no thumbprint)
    }
  }

  # The state holds the OIDC provider and the role: no secret. Same bucket as the other stacks.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-grafana-federation/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
}
