output "budget_name" {
  description = "Monthly cost budget name."
  value       = aws_budgets_budget.monthly.name
}

output "anomaly_monitor_arn" {
  description = "Cost anomaly monitor ARN."
  value       = aws_ce_anomaly_monitor.service.arn
}
