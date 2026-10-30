terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Management-account alerting (Slack alert delivery Lambda, topics, secret, shared-component
  # alarms). Same convention as shr-iam/shr-backup-dr: account-level, rarely changes, applied
  # manually by an admin — not from CI.
  #
  # ONE DEPLOYMENT = ONE ENVIRONMENT IN ONE REGION. You pass the environment and the region of the customers
  # you are serving; nothing loops over environments or regions. Each deployment needs its own state:
  # use one workspace per deployment, named <environment>-<region>.
  #
  #   terraform workspace new prd-us-east-1        (first time; later: workspace select)
  #   terraform apply -var environment=prd -var region=us-east-1
  #
  # The workspace_guard below (DISABLED for now) would stop a plan or apply whose workspace is not named
  # <environment>-<region>. Without it nothing checks it: select the right workspace yourself, because with
  # the wrong one an apply would overwrite the state of another environment or region.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-monitoring/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # The cost of the monitoring itself, apart from the customers' (their environments tag their own resources).
  # CostCenter has to be an active cost allocation tag in Billing to show in Cost Explorer.
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      CostCenter  = "platform-monitoring"
    }
  }
}

# DISABLED (not needed yet): the check that the workspace is named <environment>-<region>. The state of a
# deployment is its workspace and the backend gives every deployment the same key, so the workspace is the only
# thing that keeps their states apart. Remove the comment markers to switch the check back on.
/*
# The state of this deployment is the workspace <environment>-<region>. The backend gives every
# deployment the same key, so the workspace is the only thing that keeps their states apart.
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = terraform.workspace == "${var.environment}-${var.region}"
      error_message = "The workspace is \"${terraform.workspace}\" but this deployment needs \"${var.environment}-${var.region}\". Run: terraform workspace select ${var.environment}-${var.region} (terraform workspace new ${var.environment}-${var.region} the first time)."
    }
  }
}
*/

variable "environment" {
  description = "Environment this deployment serves: dev, stg or prd, or the full environment name for any other (e.g. demo-foo). It gets its own alert delivery Lambda, IAM role, Slack webhook secret and alert topics, so the alerts of the customer environments wired to it reach only its Slack channels. The wiring is by name: customer environments derive the same name from their own environment name (customer-monitoring). The topic policy takes alarms from any account and does not check the environment, so this separation is not enforced by the topics."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-13 characters: lowercase letters, digits and hyphens, not starting or ending with a hyphen (it is part of IAM role names)."
  }
}

variable "region" {
  description = "Region of this deployment's alert delivery Lambda and alert topics. Customer alarms publish to the topics of their own region (CloudWatch cannot publish to another region's topic), so deploy once per tier and region that hosts customers."
  type        = string
}

variable "slack_webhook_secret_arn" {
  description = "ARN of an existing secret, in this region, holding this environment's Slack Incoming Webhook URLs. Null (default) creates an empty secret, lighthouse-alerting-<environment>-<region>-slack-webhooks; set its value with the AWS CLI after the first apply (value: JSON {\"Operations\": \"<url>\", \"Engineering\": \"<url>\"})."
  type        = string
  default     = null
}

variable "network_firewall_name" {
  description = "Shared Network Firewall in the Management VPC. Null skips the dropped-packets alarm."
  type        = string
  default     = null
}

variable "network_firewall_availability_zones" {
  description = "Availability zones the firewall has endpoints in (at most 4)"
  type        = list(string)
  default     = []
}

variable "dashboard_url" {
  description = "Grafana Platform dashboard URL included in management-account alerts"
  type        = string
  default     = null
}

variable "cost_customers" {
  description = "Customers whose cost to watch, keyed by customer code (or environment name): a monthly budget and a cost anomaly monitor each (modules/cost-monitoring), alerting this deployment's P3 and P2 topics. instance is the value of the Instance tag on that customer's resources (unique per customer environment, activated in Billing > Cost Allocation Tags). Budgets are account-wide: fill this in ONE deployment per environment (two regions of the same environment would collide on the budget names). Empty (default) creates no budget or monitor. The P2 and P3 topics and their key always allow AWS Budgets and Cost Anomaly Detection of this account (alert-delivery), so cost monitoring only needs this map filled in."
  type = map(object({
    instance              = string
    monthly_budget_usd    = number
    anomaly_threshold_usd = optional(number)
  }))
  default = {}
}

variable "cost_default_anomaly_threshold_usd" {
  description = "Minimum cost anomaly (USD) that alerts P3, for a customer that sets no anomaly_threshold_usd of its own"
  type        = number
  default     = 100
}

# DISABLED (the Grafana role is not used): see modules/alert-delivery/grafana.tf.
/*
variable "grafana_account_id" {
  description = "AWS account ID Grafana runs in. Null skips the management-account read-only role."
  type        = string
  default     = null
}
*/

# DISABLED (the IAM user is not used): see modules/alert-delivery/grafana.tf.
/*
variable "grafana_user_enabled" {
  description = "Create an IAM user with the read-only Grafana policy, for a Grafana server that has no AWS identity (the data source then uses Access & secret key). No access key is created here: make it by hand from the grafana_user_name output."
  type        = bool
  default     = false
}
*/

# The module was called alert_formatter: keep the state of the deployed resources under the new name.
moved {
  from = module.alert_formatter
  to   = module.alert_delivery
}

module "alert_delivery" {
  source = "../../modules/alert-delivery"

  region                              = var.region
  environment                         = var.environment
  slack_webhook_secret_arn            = var.slack_webhook_secret_arn
  network_firewall_name               = var.network_firewall_name
  network_firewall_availability_zones = var.network_firewall_availability_zones
  dashboard_url                       = var.dashboard_url
  # grafana_account_id = var.grafana_account_id # DISABLED (the Grafana role is not used)
  # grafana_user_enabled = var.grafana_user_enabled # DISABLED (the IAM user is not used)
}

# Budgets and cost anomaly monitors of the customers. After alert_delivery, whose topic policy and key policy have
# to allow AWS Budgets and Cost Anomaly Detection before a budget or subscription can publish to the topics.
module "cost_monitoring" {
  source = "../../modules/cost-monitoring"

  environment                   = var.environment
  alert_topic_arns              = module.alert_delivery.alert_topic_arns
  customers                     = var.cost_customers
  default_anomaly_threshold_usd = var.cost_default_anomaly_threshold_usd

  depends_on = [module.alert_delivery]
}

output "slack_webhook_secret_arn" {
  description = "Secret to put this environment's Slack webhook URL(s) into: aws secretsmanager put-secret-value --secret-id <this> --secret-string ..."
  value       = module.alert_delivery.slack_webhook_secret_arn
}

output "formatter_lambda_arn" {
  description = "ARN of this environment's alert delivery Lambda in this region (informational: customer environments build the topic ARNs themselves)"
  value       = module.alert_delivery.formatter_lambda_arn
}

output "alert_topic_arns" {
  description = "Priority => ARN of this environment's alert topics in this region. A customer environment of the same name and region builds the same ARNs from management_account_id."
  value       = module.alert_delivery.alert_topic_arns
}

output "management_account_id" {
  description = "Set as management_account_id in each customer environment"
  value       = module.alert_delivery.management_account_id
}

# DISABLED (the IAM user is not used): see modules/alert-delivery/grafana.tf.
/*
output "grafana_user_name" {
  description = "IAM user for Grafana's data source when the server has no AWS identity (null unless grafana_user_enabled). Make its access key by hand: aws iam create-access-key --user-name <this>"
  value       = module.alert_delivery.grafana_user_name
}
*/

# DISABLED (the Grafana role is not used): see modules/alert-delivery/grafana.tf.
/*
output "grafana_role_arn" {
  description = "Assume Role ARN for Grafana's management-account CloudWatch data source (null unless grafana_account_id is set)"
  value       = module.alert_delivery.grafana_role_arn
}
*/

output "cost_budget_names" {
  description = "Customer key => name of its monthly budget (empty without cost_customers)"
  value       = module.cost_monitoring.budget_names
}
