output "customer_data_sources" {
  description = "Customer name => uid of its CloudWatch data source"
  value       = { for name, ds in grafana_data_source.customer : name => ds.uid }
}

output "management_data_source_uid" {
  description = "uid of the management account's CloudWatch data source (null when management_grafana_role_arn is not set)"
  value       = one(grafana_data_source.cloudwatch_management[*].uid)
}
