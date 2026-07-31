output "gateway_instance_id" {
  description = "Current gateway EC2 instance ID."
  value       = aws_instance.gateway.id
}

output "gateway_primary_network_interface_id" {
  description = "Primary ENI used as the VPC routing target during replacement."
  value       = aws_instance.gateway.primary_network_interface_id
}

output "gateway_elastic_ip" {
  description = "Elastic IP consumed by DNS-only WireGuard endpoint records."
  value       = aws_eip.gateway.public_ip
}

output "gateway_security_group_id" {
  description = "Gateway security group admitting three public WireGuard UDP ports and private routed traffic with no inbound TCP."
  value       = aws_security_group.gateway.id
}

output "wireguard_interfaces" {
  description = "Effective three-interface WireGuard network contract."
  value       = local.wireguard_interfaces
}

output "wireguard_secret_arn" {
  description = "WireGuard recovery secret container ARN; no secret version is managed by Terraform."
  value       = aws_secretsmanager_secret.wireguard.arn
}

output "adguard_secret_arn" {
  description = "AdGuard recovery secret container ARN; no secret version is managed by Terraform."
  value       = aws_secretsmanager_secret.adguard.arn
}

output "public_key_parameter_paths" {
  description = "Exact SSM paths the gateway may overwrite with derived public keys; Terraform creates no parameter values."
  value       = local.public_key_parameter_paths
}

output "runtime_instance_profile_name" {
  description = "Steady-state read-only gateway instance profile."
  value       = aws_iam_instance_profile.runtime.name
}

output "bootstrap_instance_profile_name" {
  description = "Temporary bootstrap profile, present only while gateway_profile_mode is bootstrap."
  value       = try(aws_iam_instance_profile.bootstrap[0].name, null)
}

output "gateway_secrets_kms_key_arn" {
  description = "KMS key protecting the gateway recovery secret containers."
  value       = aws_kms_key.gateway.arn
}
