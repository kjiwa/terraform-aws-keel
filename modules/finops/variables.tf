variable "name_prefix" {
  description = "Prefix for every resource name this module creates (string, lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "alert_email" {
  description = "Address that receives budget-threshold and cost-anomaly emails (string). Budgets and Cost Explorer deliver directly by email, so there is no SNS subscription to confirm."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD (number). Notifications fire at 80% of actual and 100% of forecasted spend. Size it a little above steady-state so normal months stay quiet but a runaway (a stuck build loop, a forgotten resource) trips it; the default suits a single small instance."
  type        = number
  default     = 15
  nullable    = false

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}
