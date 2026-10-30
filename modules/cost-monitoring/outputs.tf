output "budget_names" {
  description = "Customer key => name of its monthly budget"
  value       = { for k, b in aws_budgets_budget.customer : k => b.name }
}

output "anomaly_monitor_arns" {
  description = "Customer key => ARN of its cost anomaly monitor"
  value       = { for k, m in aws_ce_anomaly_monitor.customer : k => m.arn }
}
