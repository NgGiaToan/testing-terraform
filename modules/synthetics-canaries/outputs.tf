output "https_availability_canary_name" {
  description = "Feed this into modules/customer-monitoring's https_availability_canary_name variable"
  value       = aws_synthetics_canary.https_availability.name
}

output "workflow_canary_name" {
  description = "Feed this into modules/customer-monitoring's synthetics_canary_name variable"
  value       = aws_synthetics_canary.workflow.name
}
