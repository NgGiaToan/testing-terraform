variable "region" {
  description = "Region of the AWS provider. IAM is global, so any region works: it only picks the API endpoint."
  type        = string
  default     = "us-east-1"
}

variable "grafana_azure_tenant_id" {
  description = "Microsoft Entra tenant ID (a GUID) of the Azure VM that runs Grafana. AWS trusts the tokens that this tenant issues (https://sts.windows.net/<tenant>/)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.grafana_azure_tenant_id))
    error_message = "grafana_azure_tenant_id is a GUID, like 11111111-2222-3333-4444-555555555555."
  }
}

variable "grafana_azure_audience" {
  description = "The audience (aud) of the Azure token that Grafana's VM presents to AWS: the Application ID URI of an Entra app registration made for this, e.g. api://aws-sts. It is the client ID of the OIDC provider and a condition of the role trust. It must match the aud claim of the token character by character."
  type        = string

  validation {
    condition     = length(var.grafana_azure_audience) > 0
    error_message = "grafana_azure_audience cannot be empty."
  }
}

variable "grafana_azure_subject" {
  description = "The subject (sub) of the token: the object (principal) ID, a GUID, of the Managed Identity attached to the Grafana VM. The role trusts only this one identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.grafana_azure_subject))
    error_message = "grafana_azure_subject is the object ID of the Managed Identity, a GUID."
  }
}

variable "role_name" {
  description = "Name of the role that Grafana's VM assumes."
  type        = string
  default     = "lighthouse-alerting-grafana-federated"
}
