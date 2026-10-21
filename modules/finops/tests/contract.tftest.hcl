mock_provider "aws" {}

variables {
  name_prefix        = "demo"
  alert_email        = "alerts@example.com"
  monthly_budget_usd = 20
}

run "names_carry_prefix" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.name == "demo-monthly"
    error_message = "The budget name must be <name_prefix>-monthly."
  }

  assert {
    condition     = aws_ce_anomaly_monitor.service.name == "demo-service-monitor"
    error_message = "The anomaly monitor name must be <name_prefix>-service-monitor."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.alerts.name == "demo-anomalies"
    error_message = "The anomaly subscription name must be <name_prefix>-anomalies."
  }
}

run "budget_shape" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "20" && aws_budgets_budget.monthly.limit_unit == "USD" && aws_budgets_budget.monthly.time_unit == "MONTHLY"
    error_message = "The budget must be the given USD amount per month."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 2
    error_message = "The budget must carry exactly the 80% actual and 100% forecasted notifications."
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.monthly.notification : contains(n.subscriber_email_addresses, "alerts@example.com")])
    error_message = "Every budget notification must email alert_email."
  }
}

run "anomaly_wiring" {
  command = plan

  assert {
    condition     = aws_ce_anomaly_monitor.service.monitor_type == "DIMENSIONAL" && aws_ce_anomaly_monitor.service.monitor_dimension == "SERVICE"
    error_message = "The anomaly monitor must be a per-service dimensional monitor."
  }

  assert {
    condition     = length(aws_ce_anomaly_subscription.alerts.monitor_arn_list) == 1
    error_message = "The anomaly subscription must watch exactly the one monitor."
  }

  assert {
    condition     = one(aws_ce_anomaly_subscription.alerts.subscriber).address == "alerts@example.com"
    error_message = "The anomaly subscription must email alert_email."
  }
}

run "default_budget_amount" {
  command = plan

  variables {
    monthly_budget_usd = null
  }

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "15"
    error_message = "Omitting monthly_budget_usd must give the documented 15 USD default."
  }
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    name_prefix = "Not Valid"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_nonpositive_budget" {
  command = plan

  variables {
    monthly_budget_usd = 0
  }

  expect_failures = [var.monthly_budget_usd]
}

run "rejects_bad_email" {
  command = plan

  variables {
    alert_email = "not-an-address"
  }

  expect_failures = [var.alert_email]
}
