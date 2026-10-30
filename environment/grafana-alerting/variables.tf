variable "grafana_url" {
  description = "URL of the Grafana Cloud stack, e.g. https://mycompany.grafana.net"
  type        = string
}

variable "grafana_token" {
  description = "Token of a Grafana service account allowed to manage data sources, folders, contact points and alert rules. Pass it as TF_VAR_grafana_token, never in a file."
  type        = string
  sensitive   = true
}

# The inputs of the rules, the contact point and the folder.
variable "region" {
  description = "Region of the management account's alert stack (the region of its Lambdas and alert topics)"
  type        = string
  default     = "ap-southeast-2"
}

variable "name_prefix" {
  description = "Name prefix of the alert stack's resources. Must match modules/alert-delivery (its shared_prefix, lighthouse-alerting); the per-environment Lambdas and topics add the environment after it."
  type        = string
  default     = "lighthouse-alerting"
}

variable "alert_environments" {
  description = "Environments that have an alert-delivery deployment in the management account (dev, stg, prd or a full environment name): each has a alert delivery Lambda <name_prefix>-<environment>-formatter and topics <name_prefix>-<environment>-alerts-p1/p2/p3 that Grafana watches. One that is not deployed yet raises no alert (no data counts as OK)."
  type        = list(string)
  default     = ["dev", "stg", "prd"]
}

variable "management_data_source_uid" {
  description = "uid of the management account's CloudWatch data source that the rules read. Created by environment/grafana-datasources (management_grafana_role_arn there); keep this equal to its uid."
  type        = string
  default     = "lighthouse-cw-management"
}

variable "slack_contact_point_name" {
  description = "Name of the EXISTING Grafana contact point that posts to Slack. The alerts on the alert pipeline go there. Use a channel for system health, apart from customer alerts."
  type        = string
}
