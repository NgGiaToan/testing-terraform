output "grafana_federated_role_arn" {
  description = "ARN of the role that Grafana's VM assumes: the value of AWS_ROLE_ARN in the Grafana process on the VM."
  value       = aws_iam_role.grafana.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider that trusts Microsoft Entra ID for this tenant and audience."
  value       = aws_iam_openid_connect_provider.azure.arn
}
