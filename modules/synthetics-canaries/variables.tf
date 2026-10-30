variable "customer_code" {
  description = "Customer code, e.g. \"cus001\" — used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. \"prod-cus001\" — used in resource names and tags"
  type        = string
}

variable "target_url" {
  description = "Customer-facing URL both canaries probe, e.g. \"https://cus001.lighthouse.example.com\""
  type        = string
}

variable "runtime_version" {
  description = "Synthetics runtime version for both canaries. Confirm the current value with `aws synthetics describe-runtime-versions` — AWS deprecates old runtimes on a schedule."
  type        = string
  default     = "syn-nodejs-puppeteer-9.0"
}

variable "https_availability_schedule_expression" {
  description = "Schedule for the HTTPS availability canary (spec: every 1 minute)"
  type        = string
  default     = "rate(1 minute)"
}

variable "workflow_schedule_expression" {
  description = "Schedule for the workflow canary (spec: every 5 minutes)"
  type        = string
  default     = "rate(5 minutes)"
}

variable "tags" {
  description = "Extra tags merged onto every resource in this module (e.g. the same Customer/Environment/Product/CostCenter/Region tags used in modules/customer-monitoring)"
  type        = map(string)
  default     = {}
}
