variable "grafana_url" {
  description = "URL of the Grafana Cloud stack, e.g. https://mycompany.grafana.net"
  type        = string
}

variable "grafana_token" {
  description = "OPTIONAL. Token of a Grafana service account allowed to manage data sources. Leave it null (default) when Grafana lets everyone in as Admin: the provider then uses \"anonymous\". Otherwise pass it as TF_VAR_grafana_token, never in a file."
  type        = string
  default     = null
  sensitive   = true
}

variable "customers" {
  description = <<-EOT
    The customers Grafana reads, one CloudWatch data source each. The key is the name of the data
    source: it is what the dashboards list in their Customer dropdown (lowercase letters, digits and
    hyphens, at most 20 characters). `environment` is the `environment` value of that customer's
    stack (dev-cus0001, staging-<env_name>, prod-<customer_code>): the read-only role is named
    <environment>-monitoring-grafana-read. `region` is the default region of the data source. Set
    `role_arn` (the grafana_role_arn output of the customer's stack) to use a role that does not
    follow that name.
  EOT
  type = map(object({
    account_id  = string
    environment = string
    region      = string
    role_arn    = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, c in var.customers : can(regex("^[a-z0-9-]{1,20}$", name))])
    error_message = "A customer key (the data source name) uses lowercase letters, digits and hyphens, at most 20 characters."
  }

  validation {
    condition     = alltrue([for c in values(var.customers) : can(regex("^[0-9]{12}$", c.account_id))])
    error_message = "account_id must be the 12-digit AWS account ID of the customer."
  }
}

variable "management_grafana_role_arn" {
  description = "ARN of the read-only role in the management account that Grafana assumes (grafana_role_arn output of environment/shr-monitoring). Null (default) creates no management data source: it is only needed for the panels that are not per customer (Network Firewall, quota, Lambda, SNS)."
  type        = string
  default     = null
}

variable "region" {
  description = "Default region of the management data source: the region of the alert stack (its Lambdas and alert topics)."
  type        = string
  default     = "ap-southeast-2"
}

variable "authentication_provider" {
  description = "How Grafana signs in to AWS (authType of the data sources). default (AWS SDK Default, the default here) is for a Grafana that you run yourself and whose server has an AWS identity (the role of its machine or task, or environment variables): it assumes the read-only role from that identity, and the role's trust policy must allow its account. grafana_assume_role is for Grafana Cloud only: Grafana assumes the role from its own AWS account, so nothing is given to it."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["grafana_assume_role", "default"], var.authentication_provider)
    error_message = "authentication_provider is default (AWS SDK Default: a Grafana you run yourself with an AWS identity) or grafana_assume_role (Grafana Cloud)."
  }
}

