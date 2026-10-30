# Grafana reads CloudWatch: the CloudWatch data sources of the Grafana Cloud stack, one for each
# customer account and, optionally, one for the management account. See README.md.
#
# This is the first step of the Grafana integration and the only one needed to read CloudWatch from
# Grafana. Watching the alert pipeline from Grafana (alert rules) is a separate stack,
# environment/grafana-alerting, for later.
#
# Grafana Cloud cannot load provisioning files, so this is a Terraform stack that talks to the Grafana
# API with a service account token. It needs no AWS credentials except for the state bucket. The
# read-only roles that the data sources assume are created in the AWS accounts by
# modules/customer-monitoring (customers) and modules/alert-delivery (management).
#
# NOT validated: written against the provider's documentation, without running `terraform validate`
# (the provider could not be loaded where this was written). Validate and pin the provider version
# before the first apply.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 3.0" # pin to the version you validated
    }
  }

  # The state holds role ARNs and data source names, no secret. Same bucket as the other stacks.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "grafana-datasources/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = coalesce(var.grafana_token, "anonymous") # "anonymous": a Grafana that lets everyone in as Admin
}
