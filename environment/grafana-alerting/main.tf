# Grafana Cloud side of the alerting: Grafana watches the alert pipeline (SNS and the Lambdas in
# the management account) and sends its own Slack alerts. See README.md.
#
# Grafana Cloud cannot load provisioning files, so this is a Terraform stack that talks to the
# Grafana API. It is separate from the AWS stacks: it needs a Grafana service account token, not
# AWS credentials.
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
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_token
}
