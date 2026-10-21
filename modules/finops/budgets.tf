# Monthly cost guardrail. Two notifications: an early warning when actual spend
# crosses 80% of the budget, and a forecast alarm when the month is projected to
# blow through it. Budgets emails the address directly -- no SNS topic, no
# subscription to confirm. AWS bills only action-enabled budgets beyond the
# first two per account; this budget has no actions.
#
# Cost-allocation tag activation is a separate, out-of-band step: in an AWS
# Organization member account, aws_ce_cost_allocation_tag returns
# AccessDenied -- activation is owned by the management (payer) account's
# Billing console, is not retroactive, and takes ~24h to surface.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
