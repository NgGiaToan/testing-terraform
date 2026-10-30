terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Cost monitoring of the customers, kept in the management account next to the alert topics (like the quota
# alarms), so the customer environments (and the CI role that applies them) need no billing permission.
#
# One budget and one cost anomaly monitor per customer, told apart by a cost allocation TAG: every resource of a
# customer carries the tag (default_tags of its environment), and the tag has to be ACTIVE in Billing > Cost
# Allocation Tags (in the payer account) or the budget reads zero spend and never alerts, without an error.
#
# Alerts go to the alert topics of the same deployment (alert-delivery), so they reach Slack through the same
# Lambda: 80% of the budget (actual) or a forecast over 100% -> P3, 100% (actual) -> P2, an anomaly -> P3.
# The topics must allow AWS Budgets and Cost Anomaly Detection: alert-delivery always does it (topic policy in
# formatter.tf, key policy in kms.tf), for this account only.

locals {
  topic_warning  = var.alert_topic_arns["P3"]
  topic_critical = var.alert_topic_arns["P2"]
}
