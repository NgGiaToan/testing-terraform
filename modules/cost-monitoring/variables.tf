variable "environment" {
  description = "Environment of the alert deployment these budgets belong to (dev, stg, prd...). It is part of every budget and monitor name, so the budgets of two environments never collide. Budgets are account-wide: set customers in ONE deployment per environment, not in each region."
  type        = string
}

variable "alert_topic_arns" {
  description = "Priority => ARN of the alert topics the alerts are sent to (the alert_topic_arns output of alert-delivery). Needs P2 and P3."
  type        = map(string)

  validation {
    condition     = contains(keys(var.alert_topic_arns), "P2") && contains(keys(var.alert_topic_arns), "P3")
    error_message = "alert_topic_arns needs the P2 and P3 topics."
  }
}

variable "customers" {
  description = "Customers to watch, keyed by a short name (the customer code, or the environment name for a customer with several). instance is the value of the Instance tag on that customer's resources and must be unique per customer environment. monthly_budget_usd is its monthly budget. anomaly_threshold_usd overrides default_anomaly_threshold_usd for this customer."
  type = map(object({
    instance              = string
    monthly_budget_usd    = number
    anomaly_threshold_usd = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.customers) : can(regex("^[a-z0-9][a-z0-9-]{0,40}$", k))])
    error_message = "A customer key is 1-41 characters: lowercase letters, digits and hyphens, starting with a letter or digit (it is part of the budget name)."
  }

  validation {
    condition     = alltrue([for c in values(var.customers) : c.monthly_budget_usd > 0 && trimspace(c.instance) != ""])
    error_message = "Every customer needs an instance and a monthly_budget_usd above 0."
  }

  validation {
    condition     = length(distinct([for c in values(var.customers) : c.instance])) == length(var.customers)
    error_message = "instance must be unique per customer: two customers with the same value would share one tag filter."
  }
}

variable "cost_tag_key" {
  description = "Key of the cost allocation tag the budgets and monitors filter on. It must tell one customer from another, so it is Instance (CostCenter is not unique per customer). Activate it in Billing > Cost Allocation Tags first."
  type        = string
  default     = "Instance"
}

variable "warning_percent" {
  description = "Percent of the budget spent (actual) that alerts P3"
  type        = number
  default     = 80
}

variable "critical_percent" {
  description = "Percent of the budget spent (actual) that alerts P2. A forecast over this percent alerts P3 (see forecast_alert_enabled)."
  type        = number
  default     = 100
}

variable "forecast_alert_enabled" {
  description = "Also alert P3 when the forecast spend goes over critical_percent of the budget"
  type        = bool
  default     = true
}

variable "default_anomaly_threshold_usd" {
  description = "Minimum cost anomaly (USD) that sends a P3 alert, unless the customer sets its own"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags for the budgets and monitors"
  type        = map(string)
  default     = {}
}
